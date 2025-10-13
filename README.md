# figma_bckp

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

---

## Сборка DMG для macOS

Инструкция по созданию установочного DMG-образа для распространения приложения.

### 1. Установка зависимостей

Убедитесь, что у вас установлен [Homebrew](https://brew.sh/). Затем установите утилиту `create-dmg`:

```bash
brew install create-dmg
```

### 2. Сборка Flutter-приложения

Соберите релизную версию macOS-приложения:

```bash
flutter build macos
```

### 3. Создание DMG-образа

Выполните следующую команду из корня проекта, чтобы создать стилизованный DMG-образ с иконкой приложения и ссылкой на папку "Программы":

```bash
create-dmg \
  --volname "Figma Bckp" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "figma_bckp.app" 150 180 \
  --hide-extension "figma_bckp.app" \
  --app-drop-link 450 180 \
  --add-file "Инструкция.txt" "assets/dmg/Инструкция.txt" 650 180 \
  "build/Figma_Bckp.dmg" \
  "build/macos/Build/Products/Release/figma_bckp.app"
```

Готовый файл `Figma_Bckp.dmg` будет находиться в папке `build`.

---

## Установка и первый запуск

После создания DMG-образа, его можно использовать для установки приложения.

1.  Откройте `Figma_Bckp.dmg`.
2.  Перетащите `figma_bckp.app` в папку `Applications` (Программы).
3.  **Важно:** macOS может блокировать запуск приложений от неустановленных разработчиков. Чтобы снять это ограничение, откройте Терминал и выполните команду:

    ```bash
    xattr -cr /Applications/figma_bckp.app
    ```

После этого приложение будет запускаться без предупреждений системы безопасности.

---

## Технические детали сборки под macOS

Этот раздел описывает ключевые технические решения, принятые для корректной работы приложения в среде macOS.

### 1. Запуск Chromium

Приложение не использует системный Google Chrome. Вместо этого оно запускает собственную, изолированную копию **Chromium**, которая вкомпилирована внутрь пакета `.app`. Запуск происходит из Dart-кода (`puppeteer_service.dart`) с помощью библиотеки `puppeteer`. Путь к исполняемому файлу Chromium находится внутри самого пакета, что гарантирует предсказуемую среду выполнения.

### 2. Разрешения и песочница (Sandbox)

Для обеспечения бесперебойной работы (скачивание файлов, управление браузером) песочница (sandbox) полностью отключена на двух уровнях:

*   **На уровне приложения (macOS Sandbox):** В файле `Release.entitlements` ключ `com.apple.security.app-sandbox` установлен в `false`. Это снимает с приложения системные ограничения macOS.
*   **На уровне браузера (Chromium Sandbox):** В коде принудительно передаются аргументы `--no-sandbox` и `--disable-setuid-sandbox` при запуске Chromium, что отключает его внутреннюю песочницу.
*   **Наследование разрешений:** Флаг `com.apple.security.inherit: true` в `.entitlements` позволяет дочернему процессу (Chromium) наследовать "беспесочный" режим от основного приложения.

### 3. Сборка проекта в Xcode

В настройках сборки Xcode (`project.pbxproj`) добавлен специальный скрипт **"Copy Chromium"**. Он рекурсивно копирует `Chromium.app` из папки `assets` проекта в финальный пакет приложения (`.app/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/chromium/`), делая его доступным для запуска из Dart-кода.

### 4. Удаление атрибута карантина

В процессе сборки выполняется еще один важный скрипт — **"Remove Quarantine Attribute"** (`xattr -cr ...`). Он принудительно снимает с финального пакета `.app` метку `com.apple.quarantine`, которую macOS Gatekeeper добавляет файлам, скачанным из интернета. Это предотвращает появление системного диалогового окна "Вы уверены, что хотите запустить это приложение?" при первом запуске, делая работу программы более гладкой для пользователя.
