# Выборочное скачивание без исходной Git-истории

Нужны Git, Python 3.9+ и Bash 3.2+ (macOS/Linux или WSL/Git Bash на Windows).
Сохраните эту папку целиком: shell-скрипту нужен Python-файл рядом и projects.tsv.
Открытые репозитории скачиваются по HTTPS без входа в GitHub.
Для закрытых в будущем потребуется доступ через свой аккаунт.

```bash
bash export-project.sh --catalog projects.tsv --list
mkdir -p "$HOME/Projects"
bash export-project.sh --catalog projects.tsv --project web-counter --dest "$HOME/Projects/Counter" --init-git
```

`--dest` задаёт нужную папку: новую или пустую; родитель должен существовать.
Выберите папку вне любых существующих Git-репозиториев. Пробелы допустимы;
путь заключайте в кавычки. Непустая папка отклоняется без удаления её файлов.
Без `--init-git` в копии вообще нет `.git`. С ним создаётся новая история
без commits/remote. Дальнейший push описан в docs/CLIENT-HANDOFF.md проекта.

Можно выбрать любой репозиторий без каталога:

```bash
bash export-project.sh --repo https://github.com/OWNER/REPOSITORY.git --ref main --dest "$HOME/Projects/My App" --init-git
```

Для воспроизводимого результата замените main на конкретный commit/tag.
Из копии исключаются `.git`, `.gitmodules`, `.github`, рабочие БД, локальные
credentials, зависимости, сборки, symlinks и этот отмеченный downloader.
Поля repository/homepage/bugs/funding в package.json очищаются. LICENSE/NOTICE
и шаблоны конфигурации сохраняются. Неизвестные явные credential values в JSON
останавливают экспорт. Проверка не заменяет аудит произвольного стороннего кода.
Submodule отклоняется: сначала нужна самостоятельная копия его исходников.
