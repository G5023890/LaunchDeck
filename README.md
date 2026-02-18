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
- `MacLaunchControl/assets/icon_cropped_square.png` — исходник иконки

## Требования

- macOS 13+
- Xcode / Swift toolchain

## Запуск в режиме разработки

```bash
cd MacLaunchControl
swift run
```

## Сборка `.app`

```bash
cd MacLaunchControl
./scripts/build_app.sh
```

Готовый bundle:

`MacLaunchControl/dist/MacLaunchControl.app`

Запуск:

```bash
open MacLaunchControl/dist/MacLaunchControl.app
```

## Иконка приложения

По умолчанию скрипт сборки берет PNG из:

`MacLaunchControl/assets/icon_cropped_square.png`

Можно переопределить через env-переменную:

```bash
ICON_SOURCE=/path/to/icon.png ./scripts/build_app.sh
```

## Примечание по расписанию

Расписание создается в user-domain (`~/Library/LaunchAgents`) через `launchctl bootstrap gui/<uid>`.
Это задачи текущего пользователя (не системные daemons).
