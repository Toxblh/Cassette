/* A small real gettext for Android.
 *
 * pixiewood builds GLib against proxy-libintl, which on non-Windows is a
 * stub: every translation call returns the msgid, so the UI stayed English
 * whatever the system language. This file replaces proxy-libintl's
 * libintl.c (build-aux/android/android.mk copies it over the subproject
 * before the build) and implements the same API by reading GNU .mo
 * catalogues: bindtextdomain()/textdomain(), language from LANGUAGE,
 * LC_ALL, LC_MESSAGES or LANG, plural forms from the catalogue header.
 * UTF-8 catalogues only (what msgfmt produces from our po files). No GLib:
 * GLib itself links against this.
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#include "libintl.h"

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int _nl_msg_cat_cntr = 0;

/* ── catalogue ──────────────────────────────────────────────────────── */

typedef struct {
  uint32_t length;
  uint32_t offset;
} MoEntry;

typedef struct Catalog {
  char *domain;
  char *lang;
  unsigned char *data;
  size_t size;
  int swap;
  uint32_t count;
  const MoEntry *orig;
  const MoEntry *trans;
  int nplurals;
  char *plural_expr;
  int loaded;                /* file existed and parsed */
  struct Catalog *next;
} Catalog;

typedef struct Binding {
  char *domain;
  char *dir;
  char *codeset;
  struct Binding *next;
} Binding;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static Binding *bindings = NULL;
static Catalog *catalogs = NULL;
static char *current_domain = NULL;

static uint32_t
rd32 (const Catalog *c, uint32_t v)
{
  return c->swap ? __builtin_bswap32 (v) : v;
}

static const char *
entry_str (const Catalog *c, const MoEntry *e, uint32_t *len)
{
  uint32_t off = rd32 (c, e->offset);
  uint32_t l = rd32 (c, e->length);
  if ((size_t) off + l >= c->size)
    return NULL;
  *len = l;
  return (const char *) c->data + off;
}

/* ── plural expression: the C-like subset used in Plural-Forms headers ── */

typedef struct { const char *p; unsigned long n; int error; } Expr;

static long pe_ternary (Expr *e);

static void
pe_skip (Expr *e)
{
  while (*e->p == ' ' || *e->p == '\t') e->p++;
}

static long
pe_primary (Expr *e)
{
  pe_skip (e);
  if (*e->p == '(') {
    e->p++;
    long v = pe_ternary (e);
    pe_skip (e);
    if (*e->p == ')') e->p++; else e->error = 1;
    return v;
  }
  if (*e->p == 'n') { e->p++; return (long) e->n; }
  if (*e->p == '!') { e->p++; return !pe_primary (e); }
  if (*e->p >= '0' && *e->p <= '9') {
    long v = 0;
    while (*e->p >= '0' && *e->p <= '9') v = v * 10 + (*e->p++ - '0');
    return v;
  }
  e->error = 1;
  return 0;
}

static long
pe_mul (Expr *e)
{
  long v = pe_primary (e);
  for (;;) {
    pe_skip (e);
    if (*e->p == '%') { e->p++; long r = pe_primary (e); v = r ? v % r : 0; }
    else if (*e->p == '*') { e->p++; v *= pe_primary (e); }
    else if (*e->p == '/') { e->p++; long r = pe_primary (e); v = r ? v / r : 0; }
    else return v;
  }
}

static long
pe_add (Expr *e)
{
  long v = pe_mul (e);
  for (;;) {
    pe_skip (e);
    if (*e->p == '+') { e->p++; v += pe_mul (e); }
    else if (*e->p == '-') { e->p++; v -= pe_mul (e); }
    else return v;
  }
}

static long
pe_cmp (Expr *e)
{
  long v = pe_add (e);
  for (;;) {
    pe_skip (e);
    if (e->p[0] == '<' && e->p[1] == '=') { e->p += 2; v = v <= pe_add (e); }
    else if (e->p[0] == '>' && e->p[1] == '=') { e->p += 2; v = v >= pe_add (e); }
    else if (e->p[0] == '<') { e->p++; v = v < pe_add (e); }
    else if (e->p[0] == '>') { e->p++; v = v > pe_add (e); }
    else return v;
  }
}

static long
pe_eq (Expr *e)
{
  long v = pe_cmp (e);
  for (;;) {
    pe_skip (e);
    if (e->p[0] == '=' && e->p[1] == '=') { e->p += 2; v = v == pe_cmp (e); }
    else if (e->p[0] == '!' && e->p[1] == '=') { e->p += 2; v = v != pe_cmp (e); }
    else return v;
  }
}

static long
pe_and (Expr *e)
{
  long v = pe_eq (e);
  for (;;) {
    pe_skip (e);
    if (e->p[0] == '&' && e->p[1] == '&') { e->p += 2; long r = pe_eq (e); v = v && r; }
    else return v;
  }
}

static long
pe_or (Expr *e)
{
  long v = pe_and (e);
  for (;;) {
    pe_skip (e);
    if (e->p[0] == '|' && e->p[1] == '|') { e->p += 2; long r = pe_and (e); v = v || r; }
    else return v;
  }
}

static long
pe_ternary (Expr *e)
{
  long c = pe_or (e);
  pe_skip (e);
  if (*e->p == '?') {
    e->p++;
    long a = pe_ternary (e);
    pe_skip (e);
    if (*e->p == ':') e->p++; else e->error = 1;
    long b = pe_ternary (e);
    return c ? a : b;
  }
  return c;
}

static int
plural_index (const Catalog *c, unsigned long n)
{
  if (c->plural_expr == NULL || c->nplurals <= 0)
    return n == 1 ? 0 : 1;
  Expr e = { c->plural_expr, n, 0 };
  long v = pe_ternary (&e);
  if (e.error || v < 0 || v >= c->nplurals)
    return n == 1 ? 0 : 1;
  return (int) v;
}

static void
parse_header (Catalog *c)
{
  uint32_t len;
  const char *hdr;
  c->nplurals = 2;
  c->plural_expr = NULL;
  if (c->count == 0)
    return;
  const char *orig = entry_str (c, &c->orig[0], &len);
  if (orig == NULL || len != 0)          /* header is the empty msgid, first */
    return;
  hdr = entry_str (c, &c->trans[0], &len);
  if (hdr == NULL)
    return;
  const char *pf = strstr (hdr, "Plural-Forms:");
  if (pf == NULL)
    return;
  const char *np = strstr (pf, "nplurals=");
  if (np)
    c->nplurals = atoi (np + 9);
  const char *pl = strstr (pf, "plural=");
  if (pl) {
    pl += 7;
    const char *end = pl;
    while (*end && *end != ';' && *end != '\n') end++;
    c->plural_expr = strndup (pl, (size_t) (end - pl));
  }
}

static Catalog *
load_catalog (const char *domain, const char *dir, const char *lang)
{
  Catalog *c = calloc (1, sizeof (Catalog));
  if (c == NULL)
    return NULL;
  c->domain = strdup (domain);
  c->lang = strdup (lang);

  char path[1024];
  snprintf (path, sizeof path, "%s/%s/LC_MESSAGES/%s.mo", dir, lang, domain);
  FILE *f = fopen (path, "rb");
  if (f == NULL)
    return c;                            /* remembered as "not there" */
  if (fseek (f, 0, SEEK_END) != 0) { fclose (f); return c; }
  long size = ftell (f);
  if (size < 28 || fseek (f, 0, SEEK_SET) != 0) { fclose (f); return c; }
  c->data = malloc ((size_t) size);
  if (c->data == NULL || fread (c->data, 1, (size_t) size, f) != (size_t) size) {
    fclose (f);
    free (c->data);
    c->data = NULL;
    return c;
  }
  fclose (f);
  c->size = (size_t) size;

  uint32_t magic = *(uint32_t *) c->data;
  if (magic == 0x950412de) c->swap = 0;
  else if (magic == 0xde120495) c->swap = 1;
  else { free (c->data); c->data = NULL; return c; }

  const uint32_t *h = (const uint32_t *) c->data;
  c->count = rd32 (c, h[2]);
  uint32_t o = rd32 (c, h[3]);
  uint32_t t = rd32 (c, h[4]);
  if ((size_t) o + c->count * sizeof (MoEntry) > c->size ||
      (size_t) t + c->count * sizeof (MoEntry) > c->size) {
    free (c->data);
    c->data = NULL;
    return c;
  }
  c->orig = (const MoEntry *) (c->data + o);
  c->trans = (const MoEntry *) (c->data + t);
  parse_header (c);
  c->loaded = 1;
  return c;
}

/* Binary search over the (sorted) original strings; key may hold NULs. */
static const char *
lookup (const Catalog *c, const char *key, size_t key_len, uint32_t *out_len)
{
  uint32_t lo = 0, hi = c->count;
  while (lo < hi) {
    uint32_t mid = lo + (hi - lo) / 2;
    uint32_t len;
    const char *s = entry_str (c, &c->orig[mid], &len);
    if (s == NULL)
      return NULL;
    size_t n = len < key_len ? len : key_len;
    int cmp = memcmp (s, key, n);
    if (cmp == 0)
      cmp = (len > key_len) - (len < key_len);
    if (cmp == 0)
      return entry_str (c, &c->trans[mid], out_len);
    if (cmp < 0) lo = mid + 1; else hi = mid;
  }
  return NULL;
}

/* ── language and domain bookkeeping ────────────────────────────────── */

static const char *
domain_dir (const char *domain)
{
  for (Binding *b = bindings; b; b = b->next)
    if (strcmp (b->domain, domain) == 0)
      return b->dir;
  return NULL;
}

/* "ru_RU.UTF-8@x" -> candidates "ru_RU", "ru"; stops at C/POSIX. */
static int
language_candidates (char out[8][32])
{
  static const char *vars[] = { "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" };
  int n = 0;
  for (size_t v = 0; v < sizeof vars / sizeof vars[0] && n < 8; v++) {
    const char *val = getenv (vars[v]);
    if (val == NULL || *val == '\0')
      continue;
    /* LANGUAGE may list several, colon separated */
    const char *p = val;
    while (*p && n < 8) {
      char item[32];
      size_t i = 0;
      while (*p && *p != ':' && i < sizeof item - 1)
        item[i++] = *p++;
      item[i] = '\0';
      if (*p == ':') p++;
      /* strip .codeset and @modifier */
      char *dot = strpbrk (item, ".@");
      if (dot) *dot = '\0';
      if (item[0] == '\0' || strcmp (item, "C") == 0 || strcmp (item, "POSIX") == 0)
        continue;
      snprintf (out[n++], 32, "%s", item);
      char *us = strchr (item, '_');
      if (us && n < 8) {
        *us = '\0';
        snprintf (out[n++], 32, "%s", item);
      }
    }
    if (n > 0 && v > 0)
      break;                             /* LC_ALL/LC_MESSAGES/LANG: first set wins */
  }
  return n;
}

static Catalog *
find_catalog (const char *domain)
{
  const char *dir = domain_dir (domain);
  if (dir == NULL)
    return NULL;
  char langs[8][32];
  int n = language_candidates (langs);
  for (int i = 0; i < n; i++) {
    Catalog *c;
    for (c = catalogs; c; c = c->next)
      if (strcmp (c->domain, domain) == 0 && strcmp (c->lang, langs[i]) == 0)
        break;
    if (c == NULL) {
      c = load_catalog (domain, dir, langs[i]);
      if (c == NULL)
        return NULL;
      c->next = catalogs;
      catalogs = c;
    }
    if (c->loaded)
      return c;
  }
  return NULL;
}

static const char *
translate (const char *domain, const char *msgid1, const char *msgid2, unsigned long n, int plural)
{
  if (msgid1 == NULL)
    return NULL;
  if (domain == NULL)
    domain = current_domain ? current_domain : "messages";

  pthread_mutex_lock (&lock);
  Catalog *c = find_catalog (domain);
  const char *result = NULL;
  if (c != NULL) {
    uint32_t tlen;
    const char *t;
    if (plural) {
      size_t l1 = strlen (msgid1), l2 = strlen (msgid2);
      char *key = malloc (l1 + 1 + l2);
      if (key) {
        memcpy (key, msgid1, l1);
        key[l1] = '\0';
        memcpy (key + l1 + 1, msgid2, l2);
        t = lookup (c, key, l1 + 1 + l2, &tlen);
        free (key);
        if (t) {
          int idx = plural_index (c, n);
          const char *form = t;
          const char *end = t + tlen;
          for (int i = 0; i < idx && form < end; i++) {
            const char *z = memchr (form, '\0', (size_t) (end - form));
            if (z == NULL) { form = NULL; break; }
            form = z + 1;
          }
          if (form && form < end)
            result = form;
        }
      }
    } else {
      t = lookup (c, msgid1, strlen (msgid1), &tlen);
      if (t && tlen > 0)
        result = t;
    }
  }
  pthread_mutex_unlock (&lock);

  if (result)
    return result;
  return plural ? (n == 1 ? msgid1 : msgid2) : msgid1;
}

/* ── the libintl API ────────────────────────────────────────────────── */

char *
gettext (const char *msgid)
{
  return (char *) translate (NULL, msgid, NULL, 0, 0);
}

char *
dgettext (const char *domainname, const char *msgid)
{
  return (char *) translate (domainname, msgid, NULL, 0, 0);
}

char *
dcgettext (const char *domainname, const char *msgid, int category)
{
  (void) category;
  return (char *) translate (domainname, msgid, NULL, 0, 0);
}

char *
ngettext (const char *msgid1, const char *msgid2, unsigned long int n)
{
  return (char *) translate (NULL, msgid1, msgid2, n, 1);
}

char *
dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n)
{
  return (char *) translate (domainname, msgid1, msgid2, n, 1);
}

char *
dcngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n, int category)
{
  (void) category;
  return (char *) translate (domainname, msgid1, msgid2, n, 1);
}

char *
textdomain (const char *domainname)
{
  pthread_mutex_lock (&lock);
  if (domainname != NULL) {
    free (current_domain);
    current_domain = strdup (domainname);
    _nl_msg_cat_cntr++;
  }
  char *r = current_domain ? current_domain : "messages";
  pthread_mutex_unlock (&lock);
  return r;
}

char *
bindtextdomain (const char *domainname, const char *dirname)
{
  if (domainname == NULL)
    return NULL;
  pthread_mutex_lock (&lock);
  Binding *b;
  for (b = bindings; b; b = b->next)
    if (strcmp (b->domain, domainname) == 0)
      break;
  if (dirname != NULL) {
    if (b == NULL) {
      b = calloc (1, sizeof (Binding));
      if (b == NULL) { pthread_mutex_unlock (&lock); return NULL; }
      b->domain = strdup (domainname);
      b->next = bindings;
      bindings = b;
    }
    free (b->dir);
    b->dir = strdup (dirname);
    _nl_msg_cat_cntr++;
  }
  char *r = b ? b->dir : NULL;
  pthread_mutex_unlock (&lock);
  return r;
}

char *
bind_textdomain_codeset (const char *domainname, const char *codeset)
{
  if (domainname == NULL)
    return NULL;
  pthread_mutex_lock (&lock);
  Binding *b;
  for (b = bindings; b; b = b->next)
    if (strcmp (b->domain, domainname) == 0)
      break;
  if (b == NULL) {
    b = calloc (1, sizeof (Binding));
    if (b == NULL) { pthread_mutex_unlock (&lock); return NULL; }
    b->domain = strdup (domainname);
    b->next = bindings;
    bindings = b;
  }
  if (codeset != NULL) {
    free (b->codeset);
    b->codeset = strdup (codeset);
  }
  char *r = b->codeset;
  pthread_mutex_unlock (&lock);
  return r;
}
