# LaunchDeck

Профессиональный macOS-инструмент для управления `launchd`/`launchctl`.

Репозиторий: https://github.com/G5023890/LaunchDeck

Лицензия: `Apache-2.0` (см. файл `LICENSE`)
Релиз: `1.0`

## Что нового

- Полный переход на `NavigationSplitView` с более плотной macOS-компоновкой
- ViewModel-driven архитектура с асинхронным выполнением shell-команд
- Новый UI в стиле Activity Monitor + Console в духе Apple Liquid Glass
- Улучшенный экран `Launch Services` с инспектором, фильтрами, сортировкой и действиями
- `Health Score` для launchd jobs с диагностикой рисков и проблем конфигурации
- `Related Jobs` и `Resources` для анализа связей процесса, plist и runtime-состояния
- `Safe Edit` для безопасного редактирования plist с валидацией, dry run и rollback
- Новый редактор launchd jobs с режимами `Structured` и `Raw`
- Обновленная иконка приложения и переименование проекта в `LaunchDeck`
- Добавлены тесты для health, relations, resource models и safe edit workflow

## Разделы приложения

- `Processes`
  - Таблица с сортировкой: `PID`, `Command`, `CPU`, `Memory`
  - `Live refresh`
  - Контекстные действия: `Kill TERM`, `Kill KILL`, `Reveal binary`, `Copy path`
- `Launch Services`
  - Фильтрация и таблица jobs: `Label`, `Domain`, `PID`, `State`, `ExitCode`
  - Цветовые индикаторы состояния и `Health Score`
  - Инспектор с секциями `Overview`, `Health Score`, `Resources`, `Related Jobs`, `Schedule`, `Actions`
  - Действия: `Load`, `Unload`, `Kickstart`, `Safe Edit`, `Reveal in Finder`, `Copy Label`
  - Ленивая загрузка resource snapshot для CPU, memory, uptime и процесса
- `User Agents` / `System Agents` / `System Daemons`
  - Представления launch jobs по доменам
- `Schedules`
  - Builder LaunchAgents (режимы `Calendar` / `Interval`)
  - Human-readable preview
  - Таблица managed agents с расчетом `Next Run`
- `Diagnostics`
  - Снимок состояния launchd (`whoami`, `launchctl manageruid`, `managerpid`, `list`)
  - Консольный вывод для быстрой диагностики
- `Safe Edit`
  - Редактор plist в режимах `Structured` и `Raw`
  - `Dry Run` перед применением изменений
  - Автоматический backup перед записью и восстановление из rollback
  - Валидация syntax, semantics и `launchctl` preflight

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
