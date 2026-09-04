# Окружение сборки Cassette под Android.
#
# Наследует образ Matras (linux/amd64, Rosetta; SDK 36, NDK 27.2.12479018, meson 1.12,
# pixiewood-зависимости) и добавляет только то, чего там нет, потому что Matras на Rust:
#   * valac — Cassette на Vala. Debian bookworm даёт 0.56.3, а его vapi для libadwaita
#     остались на 1.2 (нет Adw.Dialog, NavigationView, ToolbarView). Поэтому 0.56.19
#     из тарболла, той же версии, что Homebrew на маке — чтобы vapi совпадали.
#     Бутстрапится системным valac, который потом удаляется вместе со своими vapi,
#     чтобы valac не подхватывал старые копии через XDG_DATA_DIRS.
#   * blueprint-compiler — .blp в data/ui. В bookworm его нет, ставится из git;
#     ему нужен python3-gi (import gi в gir.py даже без введённых типов).
#
# Чего здесь НЕТ: libadwaita-1.vapi и libsoup-3.0.vapi — их vala не поставляет
# (это продукты самих библиотек), а кросс-сборка их gir/vapi под Android
# невозможна. Снимки лежат в build-aux/android/vapi/ и подключаются через
# --vapidir в meson.build при host_machine.system() == 'android'.
#
# Собирать:  docker build --platform linux/amd64 -t cassette-android-build:latest build-aux/android/
FROM --platform=linux/amd64 matras-android-build:latest

ENV DEBIAN_FRONTEND=noninteractive
ARG VALA_VERSION=0.56.19
ARG BLUEPRINT_VERSION=v0.20.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      valac flex bison libglib2.0-dev libgirepository1.0-dev python3-gi \
      autoconf automake libtool \
    && rm -rf /var/lib/apt/lists/*

RUN set -e; cd /tmp; \
    curl -fsSL -o vala.tar.xz "https://download.gnome.org/sources/vala/${VALA_VERSION%.*}/vala-${VALA_VERSION}.tar.xz" \
      || curl -fsSL -o vala.tar.xz "https://ftp.gnome.org/pub/GNOME/sources/vala/${VALA_VERSION%.*}/vala-${VALA_VERSION}.tar.xz"; \
    tar xf vala.tar.xz; cd "vala-${VALA_VERSION}"; \
    ./configure --prefix=/usr/local --disable-valadoc > /dev/null; \
    make -j"$(nproc)" > /tmp/vala-build.log 2>&1 || { tail -50 /tmp/vala-build.log; exit 1; }; \
    make install > /dev/null; \
    cd /; rm -rf /tmp/vala.tar.xz "/tmp/vala-${VALA_VERSION}"; \
    dpkg --purge --force-depends valac valac-bin valac-0.56-vapi libvalacodegen-0.56-0 libvala-0.56-0 > /dev/null; \
    rm -rf /usr/share/vala-0.56 /usr/share/vala; \
    ldconfig

RUN set -e; cd /tmp; \
    git clone -q --depth 1 --branch "${BLUEPRINT_VERSION}" https://gitlab.gnome.org/GNOME/blueprint-compiler.git \
      || git clone -q --depth 1 --branch "${BLUEPRINT_VERSION}" https://github.com/GNOME/blueprint-compiler.git; \
    cd blueprint-compiler; \
    meson setup _build --prefix=/usr/local -Ddocs=false > /dev/null; \
    meson install -C _build > /dev/null; \
    cd /; rm -rf /tmp/blueprint-compiler

# valac сверяет --target-glib с версией glib-2.0 из pkg-config ХОСТА и молча
# опускает цель до неё: с glib 2.74 из bookworm StringBuilder.free_and_steal
# (2.76) становится «недоступен», хотя линкуемся с glib 2.88 из subproject.
# Обёртка подсовывает valac фиктивный glib-2.0.pc только для этой проверки;
# на meson и настоящий pkg-config она не влияет.
RUN set -e; \
    mkdir -p /opt/vala-pc; \
    printf 'Name: glib-2.0\nDescription: version stub for valac --target-glib\nVersion: 2.88.0\n' > /opt/vala-pc/glib-2.0.pc; \
    mv /usr/local/bin/valac /usr/local/bin/valac.real; \
    printf '#!/bin/sh\nexport PKG_CONFIG_PATH="/opt/vala-pc${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"\nexec /usr/local/bin/valac.real "$@"\n' > /usr/local/bin/valac; \
    chmod +x /usr/local/bin/valac

# Проверка тем же login-шеллом, которым запускаются задания (урок из JOURNAL.md Matras).
RUN bash -lc 'set -e; \
    echo "valac      $(valac --version)"; \
    echo "blueprint  $(blueprint-compiler --version)"; \
    test -f /usr/local/share/vala-0.56/vapi/gtk4.vapi || { echo "нет gtk4.vapi"; exit 1; }; \
    test -f /usr/local/share/vala-0.56/vapi/json-glib-1.0.vapi || { echo "нет json-glib-1.0.vapi"; exit 1; }; \
    python3 -c "import gi" || { echo "нет python3-gi для blueprint"; exit 1; }; \
    printf "void main () { var b = new StringBuilder (); string s = b.free_and_steal (); print (s); }" > /tmp/t.vala; \
    valac --target-glib 2.88 -C -d /tmp /tmp/t.vala || { echo "valac всё ещё режет target-glib"; exit 1; }; \
    rm -f /tmp/t.vala /tmp/t.c; \
    ! test -e /usr/share/vala-0.56/vapi/glib-2.0.vapi || { echo "системные vapi 0.56.3 не удалены"; exit 1; }; \
    echo "OK: valac и blueprint на месте"'

WORKDIR /work
