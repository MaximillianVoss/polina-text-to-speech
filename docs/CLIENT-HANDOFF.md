# Запуск и перенос в свой GitHub

Маршрут: README → условия в docs → запуск → проверки приложения → новый GitHub.

## Запуск

macOS/Linux и Windows через WSL/Git Bash: `bash ./build-and-run.sh`.
Для выбора этапа: `bash ./build-and-run.sh --project stages/ИМЯ`.
Список приложений: `bash ./build-and-run.sh --list`.
Проверка сборки и HTTP с автоматической остановкой: `bash ./build-and-run.sh --smoke-test --no-open`.
Только сборка: `bash ./build-and-run.sh --build-only`.
По умолчанию тесты включены. `--skip-tests` используйте только осознанно.

Нужны зависимости, перечисленные в README приложения. Для Expo используется
локальная CLI проекта; по умолчанию открывается Expo Go, реальное устройство
подключают отдельно. `--expo-platform web --install-web-deps` явно выбирает web.
Для Spring публичный endpoint проверки задают `--spring-ready-path /путь`
или одной строкой в `.spring-ready-path`; параметр CLI имеет приоритет.
Готовность подтверждает только HTTP 2xx; redirect, 401 и 403 не считаются успехом.

## Свой репозиторий

Чистый экспорт не содержит чужую историю, remote, submodules, `.github` workflows
и локальные базы/секреты. LICENSE, NOTICE, схемы и примеры конфигурации сохраняются.
Новый Git создаётся только с `--init-git`; в нём нет commits и remote.
Если Git ещё не создан, в папке проекта выполните `git init`.
Создайте пустой репозиторий в своём GitHub и выполните:

```bash
git add .
git commit -m "Первоначальная версия проекта"
git branch -M main
git remote add origin https://github.com/YOUR-LOGIN/YOUR-REPOSITORY.git
git push -u origin main
```

Замените YOUR-LOGIN/YOUR-REPOSITORY своими значениями. Для push используйте
свой вход в GitHub. Параметры Firebase/API заполните своими значениями из примеров.
Публичные демо-логины в учебном коде предназначены для локального знакомства.
