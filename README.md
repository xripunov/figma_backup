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
