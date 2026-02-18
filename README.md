# LaunchDeck

Профессиональный macOS-инструмент для управления `launchd`/`launchctl`.

Репозиторий: https://github.com/G5023890/LaunchDeck

## Что нового

- Полный переход на `NavigationSplitView`
- ViewModel-driven архитектура с асинхронным выполнением shell-команд
- Новый UI в стиле Activity Monitor + Console
- Переименование приложения и проекта в `LaunchDeck`
- Обновленная иконка приложения

## Разделы приложения

- `Processes`
  - Таблица с сортировкой: `PID`, `Command`, `CPU`, `Memory`
  - `Live refresh`
  - Контекстные действия: `Kill TERM`, `Kill KILL`, `Reveal binary`, `Copy path`
- `Launch Services`
  - Фильтрация и таблица jobs: `Label`, `Domain`, `PID`, `State`, `ExitCode`
  - Цветовые индикаторы состояния (running/loaded/crashed)
  - Инспектор с секциями `General`, `Schedule`, `Runtime`
  - Действия: `Load`, `Unload`, `Kickstart`, `Edit plist`, `Reveal`
- `User Agents` / `System Agents` / `System Daemons`
  - Представления launch jobs по доменам
- `Schedules`
  - Builder LaunchAgents (режимы `Calendar` / `Interval`)
  - Human-readable preview
  - Таблица managed agents с расчетом `Next Run`
- `Diagnostics`
  - Снимок состояния launchd (`whoami`, `launchctl manageruid`, `managerpid`, `list`)
  - Консольный вывод для быстрой диагностики

## Технические требования

- macOS 14+
- Xcode / Swift toolchain (Swift 6)

## Структура проекта

- `LaunchDeck/` — Swift Package с исходниками приложения
- `LaunchDeck/Sources/LaunchctlDesktopApp/` — UI, ViewModels, services, models
- `LaunchDeck/scripts/build_app.sh` — сборка `.app`
- `LaunchDeck/assets/icon_cropped_square.png` — исходник иконки
- `LaunchDeck/dist/` — собранный `.app`

## Локальный запуск

```bash
cd LaunchDeck
swift run LaunchDeck
```

## Сборка приложения

```bash
cd LaunchDeck
./scripts/build_app.sh
```

Результат:

`LaunchDeck/dist/LaunchDeck.app`

Запуск:

```bash
open LaunchDeck/dist/LaunchDeck.app
```

Установка в `/Applications`:

```bash
ditto LaunchDeck/dist/LaunchDeck.app /Applications/LaunchDeck.app
```
