#!/usr/bin/env bash
# Экспорт одного проекта без исходной истории и remote. Bash 3.2+.
set -eo pipefail
usage() {
  cat <<'USAGE'
Использование:
  bash export-project.sh --repo URL --ref main --path . --dest "/папка/Мой проект"
  bash export-project.sh --catalog projects.tsv --project web-counter --dest "/папка/Counter"
  bash export-project.sh --catalog projects.tsv --list

  --repo URL       GitHub SSH/HTTPS URL или локальный репозиторий для офлайн-проверки.
  --ref REF        Ветка, тег или commit (по умолчанию HEAD).
  --path ПУТЬ      Каталог внутри репозитория (по умолчанию .).
  --dest ПАПКА     Новая или пустая папка; родитель должен существовать.
  --catalog TSV    Каталог: id, repo, ref, path (4 колонки TAB; # — комментарий).
  --project ID     Выбрать ровно одну строку из каталога.
  --list           Показать id из каталога, ничего не экспортировать.
  --init-git       Создать новую локальную .git без commit и без remote.

Нужны Git и Python 3.9+. Для закрытого repo понадобится доступ через свой аккаунт.
Открытые GitHub repo скачиваются по HTTPS без входа. Исходный репозиторий не меняется.
Непустую папку, ссылку и папку внутри существующего Git-репозитория скрипт отклонит.
Исключаются только из новой копии: Git metadata, ссылки, зависимости, сборки,
.env, известные файлы ключей/credentials, рабочие БД, локальные конфиги и caches.
.env.example, схемы и лицензии сохраняются. .github и отмеченный набор downloader
удаляются; package.json теряет repository/homepage/bugs/funding. README теряет
только отмеченный блок upstream-tools. Исходная Git-история не копируется.
USAGE
}
die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo=""; ref="HEAD"; project_path="."; destination=""; catalog=""; project_id=""
list_only=0; init_git=0; explicit_source=0; work=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo|--ref|--path|--dest|--catalog|--project)
      [[ $# -ge 2 && -n "$2" ]] || die "после $1 требуется значение."
      case "$1" in
        --repo) repo="$2"; explicit_source=1 ;;
        --ref) ref="$2"; explicit_source=1 ;;
        --path) project_path="$2"; explicit_source=1 ;;
        --dest) destination="$2" ;;
        --catalog) catalog="$2" ;;
        --project) project_id="$2" ;;
      esac
      shift 2 ;;
    --list) list_only=1; shift ;;
    --init-git) init_git=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "неизвестный параметр: $1" ;;
  esac
done
command -v git >/dev/null 2>&1 || die "Git не найден."
python_cmd=()
for python_candidate in python python3; do
  if command -v "$python_candidate" >/dev/null 2>&1 && "$python_candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
    python_cmd=("$python_candidate")
    break
  fi
done
if [[ ${#python_cmd[@]} -eq 0 ]] && command -v py >/dev/null 2>&1 && py -3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
  python_cmd=(py -3)
fi
[[ ${#python_cmd[@]} -gt 0 ]] || die "Нужен Python 3.9+: команда python, python3 или py -3."
[[ -f "$script_dir/export_project.py" ]] || die "рядом должен находиться export_project.py."
if [[ -n "$catalog" ]]; then
  [[ $explicit_source -eq 0 ]] || die "не смешивайте --catalog с --repo/--ref/--path."
  [[ -f "$catalog" ]] || die "каталог не найден."
  if [[ $list_only -eq 1 ]]; then
    "${python_cmd[@]}" "$script_dir/export_project.py" catalog "$catalog"
    exit 0
  fi
  [[ -n "$project_id" ]] || die "укажите --project ID."
  resolved="$("${python_cmd[@]}" "$script_dir/export_project.py" catalog "$catalog" "$project_id")"
  IFS=$'\t' read -r repo ref project_path <<< "$resolved"
elif [[ -n "$project_id" || $list_only -eq 1 ]]; then
  die "--project и --list требуют --catalog."
fi
[[ -n "$repo" && -n "$destination" ]] || die "нужны --repo и --dest (см. --help)."
[[ "$repo" != -* && "$ref" != -* ]] || die "URL/ref не могут начинаться с -."
[[ "$ref" != *$'\n'* && "$ref" != *$'\r'* && "$repo" != *$'\n'* ]] || die "URL/ref содержат перевод строки."
[[ "$repo" != http*://*@* ]] || die "не помещайте пароль/token в URL; используйте SSH или credential helper."
project_path="$("${python_cmd[@]}" "$script_dir/export_project.py" source-path "$project_path")"
destination="$("${python_cmd[@]}" "$script_dir/export_project.py" destination "$destination")"
parent="$(dirname -- "$destination")"
work="$(mktemp -d "$parent/.project-export.XXXXXX")"
cleanup() {
  local result=$?
  trap - EXIT
  # Только созданная нами временная папка; никогда не папка назначения.
  if [[ -n "$work" && -d "$work" && ! -L "$work" && "$work" == "$parent/.project-export."* ]]; then
    rm -rf -- "$work"
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git -c init.templateDir= init --bare --quiet "$work/source.git"
git --git-dir="$work/source.git" -c advice.detachedHead=false -c protocol.ext.allow=never -c protocol.helper.allow=never fetch --quiet --depth=1 -- "$repo" "$ref"
commit="$(git --git-dir="$work/source.git" rev-parse --verify 'FETCH_HEAD^{commit}')"
tree="$commit^{tree}"
if [[ "$project_path" != "." ]]; then tree="$commit:$project_path"; fi
[[ "$(git --git-dir="$work/source.git" cat-file -t "$tree")" == tree ]] || die "--path должен обозначать каталог репозитория."
git --git-dir="$work/source.git" ls-tree -r "$tree" > "$work/tree.txt"
if grep -q '^160000 ' "$work/tree.txt"; then
  die "в проекте есть submodule: подготовьте самостоятельный пакет с его исходниками."
fi
git --git-dir="$work/source.git" archive --format=tar "$tree" > "$work/source.tar"
"${python_cmd[@]}" "$script_dir/export_project.py" extract "$work/source.tar" "$work/payload"
if [[ $init_git -eq 1 ]]; then
  git -c init.templateDir= init --quiet --template= "$work/payload"
  [[ -z "$(git -C "$work/payload" remote)" ]] || die "новый Git неожиданно содержит remote."
fi
"${python_cmd[@]}" "$script_dir/export_project.py" publish "$work/payload" "$destination" "$init_git"
printf 'Готово: %s\n' "$destination"
if [[ $init_git -eq 1 ]]; then
  echo 'Создан новый локальный Git без remote и без исходной истории.'
else
  echo 'Git metadata отсутствует. Для своего репозитория выполните git init в новой папке.'
fi
