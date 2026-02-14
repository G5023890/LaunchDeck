# Visualisation-launchctl

Нативное macOS приложение (`SwiftUI`) для работы с `launchctl`.

## Что умеет

- Показывает запущенные процессы (`ps`)
- Показывает список `launchctl` jobs
- Фильтрует jobs по `Label` (вкладка `launchctl`)
- Копирует полный `Label` в буфер обмена
- Создает и управляет пользовательскими расписаниями через `LaunchAgents`

## Структура

- `MacLaunchControl/` — исходники приложения
- `MacLaunchControl/scripts/build_app.sh` — сборка `.app` bundle

## Требования

- macOS 13+
- Xcode / Swift toolchain

## Запуск в режиме разработки

```bash
cd /Users/grigorymordokhovich/Documents/Develop/Visualisation-launchctl/MacLaunchControl
swift run
```

## Сборка `.app`

```bash
cd /Users/grigorymordokhovich/Documents/Develop/Visualisation-launchctl/MacLaunchControl
./scripts/build_app.sh
```

Готовый bundle:

`/Users/grigorymordokhovich/Documents/Develop/Visualisation-launchctl/MacLaunchControl/dist/MacLaunchControl.app`

Запуск:

```bash
open /Users/grigorymordokhovich/Documents/Develop/Visualisation-launchctl/MacLaunchControl/dist/MacLaunchControl.app
```

## Иконка приложения

Скрипт сборки берет PNG из:

`/Users/grigorymordokhovich/Downloads/icon_cropped_square.png`

и генерирует `AppIcon.icns` внутри bundle.

## Примечание по расписанию

Расписание создается в user-domain (`~/Library/LaunchAgents`) через `launchctl bootstrap gui/<uid>`.
Это задачи текущего пользователя (не системные daemons).
