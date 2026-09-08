# AGENTS.md — заметки для агентов

## Android-порт: как он устроен и как был сделан

Ветка `android`. Сборка через [pixiewood](https://github.com/sp1ritCS/gtk-android-builder):
один meson/ninja-проход собирает GTK-стек и Cassette в `libcassette.so`, Gradle пакует APK
с Java-глю из GTK. Всё платформенное лежит в `build-aux/android/` (там есть README) и
`src/android/`; Vala-код гейтится `#if ANDROID`. Короткая инструкция «собрать-поставить-проверить»
— в скилле `.claude/skills/android-build/SKILL.md`.

### Архитектура (что от чего зависит)

| Слой | Десктоп | Android |
|---|---|---|
| Поток | `GstPlayerBackend` (playbin) | `AndroidPlayerBackend` → `src/android/android-player.c` (JNI) → `PlayerBridge.java` (MediaPlayer, аудиофокус) |
| Внешнее управление | MPRIS / macOS Now Playing | `src/android/now-playing.vala` → `android-now-playing.c` → `SessionBridge.java` (MediaSession) + `PlaybackService.java` (foreground) |
| Вход | WebKitGTK / WKWebView | `AuthWebView.java` — WebView полноэкранным диалогом поверх текущей Activity (GTK-активити не уходит в паузу и не пересоздаётся, что на EMUI оставляло приложение на «загрузке»); `AuthActivity` — запасной путь без активити в фокусе; через `android-auth.c`; ещё запаснее — ручной ввод токена |
| TLS | GIO-модуль | glib-networking (openssl) статически, `g_io_openssl_load (null)` в `main.vala` |
| Цвета под системными панелями | — | патч GTK-глю `build-aux/android/patches/`, `android-bars.c`, `Window.update_android_bars ()` |

`PlayerBackend` (`src/client/player/backend.vala`) — единственный контракт, который видит
логика очереди. Два адаптера на один `Player` (MPRIS и MediaSession) — намеренно раздельные,
общий знаменатель был бы хуже обоих.

### Мосты Java ↔ native

* `CassetteApplication extends RuntimeApplication` (подставляется в манифест патчером) делает
  `System.loadLibrary("cassette")` до старта GTK-рантайма, иначе JNI не находит `Java_*`-методы,
  и передаёт Context в `Native.nativeInit`. Native хранит JavaVM, Context и class loader
  приложения как GlobalRef: `FindClass` с нативного потока видит только системный загрузчик.
* Все колбэки из Java прыгают в GLib через `g_idle_add` (`cassette_jni_idle`).
* Команды из Vala приходят на GTK-потоке и постятся в Java main looper; `position()` читается напрямую.

### Что pixiewood не умеет и как это обходится

* Хуков для манифеста и своих Java-исходников нет: `patch-android-project.py` правит сгенерённый
  `AndroidManifest.xml` (permissions, application class, service, activity), копирует Java и пишет
  цветовые ресурсы. Запускается между `generate` и `build`; `build` ничего не перегенерирует.
* Симлинкуется только `org/gtk/android` — наш пакет `space.rirusha.cassette` живёт в копии.
* Патчи на подпроект GTK накладываются в `android-patch-gtk` после `prepare` (`git apply`, идемпотентно).
* Только `arm64-v8a`; `install --tags runtime`, поэтому gschema помечена `install_tag: 'runtime'`,
  а переводы (`i18n`) в APK не попадают.

### Грабли, на которые уже наступили

* **valac режет `--target-glib`** до версии glib из pkg-config хоста (2.74 в bookworm), хотя
  линкуемся с 2.88 из subproject → в образе valac обёрнут с фиктивным `glib-2.0.pc`.
* **blueprint-compiler** нужны свежие typelib Gtk/Adw — в контейнере их нет, `.blp` компилируются
  на хосте в `build-aux/android/ui/` (docker-build.sh), meson на Android их копирует.
* **libadwaita-1.vapi / libsoup-3.0.vapi** vala не поставляет; снимки лежат в `build-aux/android/vapi/`.
* **`org.gnome.desktop.peripherals.touchpad`** — GNOME-схема, на Android её нет; сделана опциональной.
* **Временный `.track`** Cassette удаляет сразу после `play()`; MediaPlayer открывает асинхронно →
  `PlayerBridge.setUri` открывает локальные файлы синхронно в fd.
* **Никогда не `stopService()` между треками**: сессия очищается и заполняется за миллисекунды,
  сервис, остановленный до `startForeground()`, убивает процесс
  (`ForegroundServiceDidNotStartInTimeException`). Только `stopForeground`.
* **Эхо паузы при потере фокуса**: `Player.pause()` в ответ на LOSS_TRANSIENT не должен сбрасывать
  `pausedByFocus` и отпускать фокус, иначе после звонка нет возобновления.
* **Кнопка «Close» на экране входа = `application.quit`** — при автоматизации тапов после появления
  поля токена кнопки сдвигаются; `main()` вернул 0 → это не падение, а выход.
* Цвет под системными панелями GDK зашивает (#353535); патч глю берёт `gtk_bars_top/bottom`
  из ресурсов и статический `setBarsColors()` в рантайме.
* Каталоги: рантайм задаёт `XDG_DATA_HOME`/`XDG_CONFIG_HOME`, но не `XDG_CACHE_HOME` и не
  `FONTCONFIG_FILE` — оба выставляются в `android_setup ()`.

### Как проверялось (чеклист на будущее)

1. Десктоп не сломан: `ninja -C build && meson test -C build` (см. память macOS-сборки).
2. APK ставится, окно рисуется, вход по токену, библиотека видна (TLS).
3. Трек играет, пауза/next/prev, перемотка, автопереход по концу трека (`dumpsys media_session`).
4. Фон после HOME, медиа-контролы в шторке, кнопки гарнитуры (`input keyevent KEYCODE_MEDIA_*`),
   звонок (`adb emu gsm call/accept/cancel`) — пауза и возобновление.
5. Цвета полос: `screencap` в raw и замер пикселей у левого края в портрете и landscape.

Вёрстка по ширине окна (не Adw.Breakpoint, см. `application-window.vala`): `PlayerBar`/`StationBar`
переключают layout `wide` → `narrow` (< 620 px) → `tiny` (< 340 px, внешние экраны раскладушек ~300 dp);
нижние бары обёрнуты в `ClipBin`, который не поднимает min-width текущего layout наверх — иначе окно
не могло бы сжаться до точки переключения. Минимум окна 280 px; проверка: `CASSETTE_DEBUG_SIZE=303x409
CASSETTE_DEBUG_MEASURE=280`, на эмуляторе `adb shell wm size 1212x1636; wm density 640` (= 303×409 dp),
назад `wm size reset; wm density reset`.

Открыто: переводы, иконка, полоса под вырезом камеры в landscape.

## Яндекс.Станции (ветка `glagol`)

Дизайн и файлы: `docs/glagol-station-control.md`. Коротко: `StationManager` — единственная
точка входа для UI (список станций из аккаунта + mDNS, подключение, состояние, перенос
туда/обратно, команды); `Player` сам отдаёт старт воспроизведения на активную станцию;
`OutputButton` → `StationPickerDialog` (bottom sheet на телефоне) → `StationBar` вместо плеербара.

* Проверять на реальной колонке — на Лайте (192.168.10.35): `CASSETTE_GLAGOL_E2E_HOST=192.168.10.35 build/tests/glagol-e2e-test -p /glagol/e2e/manager`
  (нужен вход в приложение: токен в `cassette.db`). `-p /glagol/e2e/leave` оставляет колонку играть
  (`CASSETTE_GLAGOL_E2E_ACTION=pause|status`) — так проверяется реконнект при старте и медиасессия на Android.
* UI без кликов: `CASSETTE_DEBUG_STATION=<device id>`, `CASSETTE_DEBUG_PICKER=1`,
  `CASSETTE_DEBUG_SHOT=<png>` — окно рендерится изнутри GTK, `screencapture` из терминала без разрешения не работает.
  `CASSETTE_DEBUG_SIZE=WxH` — стартовый размер окна вместо сохранённого; `CASSETTE_DEBUG_MEASURE=<px>` — через 9 с
  в лог падают все виджеты, чья минимальная ширина больше `<px>` (кто не даёт окну сжаться), плюс min обоих баров.
  На Android переменные окружения через `adb shell am start` не передать — строки `KEY=VALUE` из
  `<external files>/debug.env` (рядом с `share/`) подхватываются при старте (`android_setup` в `src/main.vala`).
* Шрифт UI на Android — статический Inter из `build-aux/android/fonts/Inter` (устанавливается в
  `share/fonts`, тег `runtime`), `gtk-font-name = "Inter 11"`. `android_setup_fonts` в `src/main.vala`
  пишет свой `fonts.conf` (include стокового + `<dir>` со шрифтами + alias'ы sans-serif/Sans/Cantarell/
  Adwaita Sans → Inter) и ставит `FONTCONFIG_FILE` на него. Через xdg-include стокового конфига это не
  работало: рантайм не экспортирует `XDG_CONFIG_HOME` в окружение процесса, и приложение молча
  рендерилось системным sans (Roboto на Pixel; MiSans VF на HyperOS — волосяная толщина и пропавшие
  пробелы). Проверка: `CASSETTE_DEBUG_FONTS=1` в `debug.env` — в лог падают семейство/начертание для
  каждого run образцов и список семейств fontconfig; там должен быть Inter.
* Поиск и страницы исполнителя/альбома (2026-09-06): `SearchView`, `ArtistView`, `AlbumView` в
  `src/widgets/views/`, собраны кодом (без blueprint), общие куски в `EntityPages` (artist.vala). API:
  `yam-client.search/artists_brief_info/albums_with_tracks`, объекты `SearchResult`, `ArtistBriefInfo`;
  `Album`/`Artist` реализуют `HasCover`, `Album`/`ArtistBriefInfo`/`SearchResult` — `HasTrackList`.
  Поиск: SearchEntry в окне → `Window.run_search` → `PageRoot.add_view (new SearchView)` или обновление
  уже открытого. Автор в панели трека кликабелен через `TrackInfoPanel.artists_activatable`.
  Снимки: `CASSETTE_DEBUG_SEARCH=<текст>`, `CASSETTE_DEBUG_ARTIST=<id>`, `CASSETTE_DEBUG_ALBUM=<id>`
  вместе с `CASSETTE_DEBUG_SHOT`. На macOS запускать с `GST_PLUGIN_SYSTEM_PATH= GST_REGISTRY=<свой файл>`,
  иначе в процесс подтягивается gtk3-плагин GStreamer и GTK падает.
* Список треков (2026-09-09): `TrackList` в `src/widgets/track-list/track-list.vala` — обёртка над
  `Gtk.ListView` (он final, поэтому `TrackList : Gtk.Widget, Gtk.Scrollable` и пробрасывает adjustments).
  Модель: `ListStore<TrackItem>` → `FilterListModel` (поиск, explicit/child/available) → `SortListModel`
  → `FlattenListModel` из [header, toolbar, empty-state, треки, footer] → `NoSelection`. Заголовок
  страницы и «хвост» (альбомы, секции поиска) — `header_widget`/`footer_widget`, они прокручиваются
  вместе со строками; `take_over (scrolled_window)` забирает содержимое шаблона в header. Виджеты строк
  создаются в `bind` и выбрасываются в `unbind`. Gtk.ListView держит первый видимый элемент на месте при
  вставке перед ним, поэтому после смены header/toolbar делается `scroll_to (0)`. Для боковой панели
  (похожие треки) — `SimpleTrackList` (обычный Box). `CASSETTE_DEBUG_PAGE=liked` вместе с
  `CASSETTE_DEBUG_SHOT` переключает страницу перед снимком. Тряска при скролле измерялась скриптом
  `shift.py` (сдвиг кадра по профилю строк raw-видео screenrecord): после переписывания развороты
  направления только там, где менялся жест.
* Аппаратные клавиши на Android: glue pixiewood (`ToplevelActivity.keyEventProxy`) возвращал `true` для любой
  клавиши, кроме Back, и клавиши громкости «съедались», пока приложение на переднем плане (жалоба с Xiaomi;
  на эмуляторе воспроизводится: `logcat` без `VolumeDialog` после `input keyevent KEYCODE_VOLUME_UP`).
  Патч `patches/gtk-android-system-keys.patch`: `KeyEvent.isSystem()` → не трогаем. Патчи на glue лежат в
  `build-aux/android/patches/gtk-*.patch`, применяются `android-patch-gtk` по алфавиту, идемпотентно.
* Вылет в `_gdk_pixbuf_get_module` из `Storager.load_image` (Xiaomi, 2026-09-08): в APK нет `loaders.cache`,
  `gdk_pixbuf_io_init()` считается неудавшейся и повторяется при каждой загрузке картинки, дописывая
  встроенные модули в `file_formats`, который читатели обходят без блокировки. Фикс: `android_setup` пишет
  пустой `$XDG_CACHE_HOME/gdk-pixbuf-loaders.cache` и ставит `GDK_PIXBUF_MODULE_FILE`; декодирование под
  `lock`. На эмуляторе не воспроизвелось (`CASSETTE_DEBUG_PIXBUF_STRESS=32` в debug.env, 9600 декодирований),
  `CASSETTE_DEBUG_NO_PIXBUF_FIX=1` возвращает старое поведение для A/B. Символизация: `llvm-symbolizer` из
  Homebrew LLVM по нестрипнутым `.pixiewood/bin-aarch64/**/*.so` (BuildId должен совпадать с логом).
* Переводы на Android (2026-09-08): pixiewood ставит `--tags runtime`, тег `i18n` пропускается —
  `po/install-mo.py` (install script с тегом runtime) копирует `.mo` в `share/locale`; `bindtextdomain` на
  Android берёт `<data_dirs[0]>/locale`. Главное: proxy-libintl вне Windows — заглушка (msgid → msgid), поэтому
  `build-aux/android/libintl/libintl.c` (своя реализация gettext по .mo, с plural forms) копируется поверх
  `subprojects/proxy-libintl-0.5/libintl.c` целью `android-patch-intl`. Язык — из `LANGUAGE`/`LANG`, которые
  `CassetteApplication` выставляет из `Locale.getDefault()` (LANG ещё и для языка API Яндекса). Проверка:
  «Проверка шрифтов…» показывает `LANGUAGE`, `Intl.get_language_names` и `_("Liked")`; эмулятор на русский:
  `adb root; setprop persist.sys.locale ru-RU; setprop ctl.restart zygote`.
* Шторка/медиасессия: уведомление не пересоздаётся между треками (очистка только по `player.stopped`),
  маленькая иконка — `cassette_symbolic` (vector из symbolic SVG в `patch-android-project.py`), кнопки
  Like и Shuffle — custom actions (`CMD_LIKE`, `CMD_SHUFFLE`).
* Анимации на Android (2026-09-09): GDK берёт `AChoreographer_getInstance()` из GTK-потока, у которого нет
  Looper → NULL, часы кадров без vsync («GdkAndroidChoreographerSource: AChoreographer_getInstance() failed»
  в logcat). Патч `patches/gtk-android-choreographer.patch`: `GlibContext.initChoreographer()` на UI-потоке
  до `startRuntime`, источник берёт этот экземпляр. Эмулятор не показатель плавности: там `init_egl failed`
  и GTK рисует софтверно (~130 мс/кадр). Инструменты: `CASSETTE_DEBUG_STALLS=1` в debug.env — стеки
  GTK-потока при паузах главного цикла > 80 мс (tag CassetteStall, символизация `scratch/symbolize.py`
  через llvm-symbolizer по `.pixiewood/bin-aarch64/**/*.so`) плюс схедстат «кто ждал CPU», и Java-вотчдог
  UI-потока (tag CassetteStallUi); `CASSETTE_DEBUG_MENU_SHOTS=<dir>` + `CASSETTE_DEBUG_DIALOG=menu|account|picker`
  открывает диалог через 8 с и логирует кадры/снимки. Перед тестами на Pixel проверять, что экран
  разблокирован (`dumpsys power | grep mWakefulness`): на заблокированном телефоне тапы и запись бесполезны.
* Blueprint на десктопе: у custom_target `blueprints` output `'.'` = `build/data`, mtime которого меняется постоянно,
  поэтому ninja **не пересобирает** `.blp` после правок. После изменения `.blp`:
  `blueprint-compiler batch-compile build/data data data/ui/*.blp`, затем `ninja -C build`.
* GSettings: `set_strv` хочет NULL-терминированный массив — `Gee.Collection.to_array()` его не даёт
  (мусор, «requires valid UTF-8»); для strv только `string[]` с `+=`.
* Токен для станции выдаётся только устройствам этого аккаунта: `glagol/token` → 404 «Unknown device»,
  если колонка в сети, но чужая. Имена и платформы — из `glagol/device_list`, mDNS даёт только
  platform/host. Платформы: `cucumber` = Станция Миди, `yandexmidi` = Станция 2, `yandexmini_2`,
  `yandexmicro` = Лайт, `yandexmodule_2`.
* mDNS-запрос идёт с QU-битом (ответы unicast): работает с любого порта и на Android без multicast lock;
  сканирование без вложенного MainLoop.
* Эмулятор Android не видит LAN-станции (NAT), список аккаунта при этом грузится; проверять на телефоне.
* Grid с `column-homogeneous` и `hexpand` у вложенных лейблов растягивают группы бара — в `StationBar`
  явный `hexpand = false` у боковых групп и `max-width-chars` у названий.
* iOS (2026-09-09, эксперимент): свой GDK-бэкенд на UIKit в `subprojects/gtk/gdk/ios` (ветка
  `ios-backend` в этом чекауте, патч в `build-aux/ios/patches`). Hello-приложение на GTK 4 рисуется и
  реагирует на тапы в симуляторе iPhone 17 (iOS 26.5). Поток GTK отдельный, UIKit на главном; рендер
  только cairo → CGImage → CALayer. Как собрать, запустить и снять логи/скриншот: `build-aux/ios/README.md`.
  Cassette под iOS ещё не собирается (нужны libsoup/TLS/gstreamer-замена/клавиатура).
