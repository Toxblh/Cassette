/* Smallest GTK app on iOS: a window with a counter button. */

#import <Foundation/Foundation.h>

#include <gtk/gtk.h>
#include <gdk/ios/gdkios.h>

static void
on_clicked (GtkButton *button, gpointer data)
{
  int *count = data;
  (*count)++;
  char *label = g_strdup_printf ("Tapped %d times", *count);
  gtk_button_set_label (button, label);
  g_free (label);
}

static void
activate (GtkApplication *app, gpointer data)
{
  GtkWidget *window = gtk_application_window_new (app);
  gtk_window_set_title (GTK_WINDOW (window), "GTK on iOS");

  GtkWidget *box = gtk_box_new (GTK_ORIENTATION_VERTICAL, 24);
  gtk_widget_set_valign (box, GTK_ALIGN_CENTER);
  gtk_widget_set_halign (box, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_top (box, 80);

  GtkWidget *title = gtk_label_new ("Hello from GTK 4");
  gtk_widget_add_css_class (title, "title-1");
  gtk_box_append (GTK_BOX (box), title);

  GtkWidget *sub = gtk_label_new ("cairo renderer, UIKit backend");
  gtk_widget_add_css_class (sub, "dim-label");
  gtk_box_append (GTK_BOX (box), sub);

  static int count = 0;
  GtkWidget *button = gtk_button_new_with_label ("Tap me");
  gtk_widget_add_css_class (button, "suggested-action");
  gtk_widget_add_css_class (button, "pill");
  g_signal_connect (button, "clicked", G_CALLBACK (on_clicked), &count);
  gtk_box_append (GTK_BOX (box), button);

  GtkWidget *sw = gtk_switch_new ();
  gtk_widget_set_halign (sw, GTK_ALIGN_CENTER);
  gtk_box_append (GTK_BOX (box), sw);

  GtkWidget *entry = gtk_entry_new ();
  gtk_entry_set_placeholder_text (GTK_ENTRY (entry), "Type here");
  gtk_box_append (GTK_BOX (box), entry);

  gtk_window_set_child (GTK_WINDOW (window), box);
  gtk_window_present (GTK_WINDOW (window));
}

static int
gtk_main_func (int argc, char **argv)
{
  /* Fonts live in the app bundle; point fontconfig at our own config. */
  NSString *resources = [[NSBundle mainBundle] resourcePath];
  char *fonts_conf = g_build_filename ([resources UTF8String], "fonts.conf", NULL);
  if (g_file_test (fonts_conf, G_FILE_TEST_EXISTS))
    g_setenv ("FONTCONFIG_FILE", fonts_conf, TRUE);
  g_free (fonts_conf);
  g_setenv ("XDG_CACHE_HOME", [NSTemporaryDirectory () UTF8String], FALSE);
  g_setenv ("XDG_DATA_HOME", [NSTemporaryDirectory () UTF8String], FALSE);
  g_setenv ("XDG_CONFIG_HOME", [NSTemporaryDirectory () UTF8String], FALSE);

  GtkApplication *app = gtk_application_new ("space.rirusha.hello", G_APPLICATION_NON_UNIQUE);
  g_signal_connect (app, "activate", G_CALLBACK (activate), NULL);
  int status = g_application_run (G_APPLICATION (app), 0, NULL);
  g_object_unref (app);
  return status;
}

int
main (int argc, char **argv)
{
  return gdk_ios_main (argc, argv, gtk_main_func);
}
