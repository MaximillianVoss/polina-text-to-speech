#!/usr/bin/env bash


# Находит вложенные Vite, Expo и Spring Boot проекты, проверяет и собирает
# их, а затем запускает выбранные приложения на свободных портах.
# Совместим со стандартным Bash 3.2 в macOS.

set -eo pipefail

print_usage() {
  cat <<'USAGE'
Использование:
  bash build-and-run.sh
  bash build-and-run.sh --list
  bash build-and-run.sh --all [--build-only] [--no-open]
  bash build-and-run.sh --select "1,5 9" [--build-only] [--no-open]
  bash build-and-run.sh --project "путь/к/проекту" [--project "ещё/один"]

Параметры:
  --list             Только показать найденные проекты.
  --all              Выбрать все найденные проекты.
  --select СПИСОК    Выбрать номера через пробел и/или запятую.
  --project ПУТЬ     Выбрать проект по пути; параметр можно повторять.
  --build-only       Проверить и собрать, но не запускать серверы.
  --no-open          Не открывать браузер/эмулятор (только сервер).
  --expo-platform P  Режим Expo: ios, android или web; иначе спросить.
  --install-web-deps Разрешить установку недостающих web-зависимостей Expo.
  --smoke-test       Проверить HTTP-готовность и сразу остановить серверы.
  --ready-timeout N  Предел ожидания HTTP-готовности (секунды; по умолчанию 90).
  --spring-ready-path ПУТЬ  Явный публичный endpoint Spring (например /login).
  --skip-tests       Не запускать автоматические тесты.
  --root ПАПКА       Искать проекты в другой корневой папке.
  --dry-run          Показать план команд без их выполнения.
  -h, --help         Показать эту справку.

Без --all, --select и --project скрипт предложит интерактивный выбор.
Вложенные папки и проекты без номера в названии поддерживаются.
Один каталог приложения показывается один раз. Этапы выбирайте через --project stages/ИМЯ.
Для остановки всех запущенных им серверов нажмите Control + C.
USAGE
}

die() {
  echo "Ошибка: $*" >&2
  exit 1
}

warn() {
  echo "Предупреждение: $*" >&2
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$script_dir"
list_only=0
select_all=0
selection_spec=""
build_only=0
no_open=0
skip_tests=0
dry_run=0
smoke_test=0
ready_timeout=90
spring_ready_path=""
project_requests=()
expo_platform=""
install_web_deps=0
project_expo_platforms=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke-test) smoke_test=1; shift ;;
    --ready-timeout)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ && ${#2} -le 4 ]] || die "--ready-timeout: целое число 1–9999."
      ready_timeout="$2"; shift 2 ;;
    --spring-ready-path)
      [[ $# -ge 2 && "$2" == /* && "$2" != //* && "$2" != *$'\n'* ]] || die "публичный endpoint должен начинаться с /."
      spring_ready_path="$2"; shift 2 ;;
    --expo-platform)
      [[ $# -ge 2 ]] || die "после --expo-platform нужно ios, android или web."
      case "$2" in ios|android|web) expo_platform="$2" ;; *) die "режим Expo: ios, android или web." ;; esac
      shift 2
      ;;
    --install-web-deps)
      install_web_deps=1
      shift
      ;;
    --list)
      list_only=1
      shift
      ;;
    --all)
      select_all=1
      shift
      ;;
    --select)
      [[ $# -ge 2 ]] || die "после --select нужен список номеров."
      selection_spec="$2"
      shift 2
      ;;
    --project)
      [[ $# -ge 2 ]] || die "после --project нужен путь."
      project_requests+=("$2")
      shift 2
      ;;
    --build-only)
      build_only=1
      shift
      ;;
    --no-open)
      no_open=1
      shift
      ;;
    --skip-tests)
      skip_tests=1
      shift
      ;;
    --root)
      [[ $# -ge 2 ]] || die "после --root нужен путь к папке."
      root_dir="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      die "неизвестный параметр '$1'. Запустите с --help."
      ;;
  esac
done

selection_modes=0
[[ $select_all -eq 1 ]] && selection_modes=$((selection_modes + 1))
[[ -n "$selection_spec" ]] && selection_modes=$((selection_modes + 1))
[[ ${#project_requests[@]} -gt 0 ]] && selection_modes=$((selection_modes + 1))
[[ $selection_modes -le 1 ]] || die "используйте только один способ выбора: --all, --select или --project."

[[ -d "$root_dir" ]] || die "корневая папка не существует: $root_dir"
root_dir="$(cd -- "$root_dir" && pwd)"

package_type() {
  local package_file="$1"

  # Vite имеет приоритет: в учебный web-репозиторий может случайно попасть
  # зависимость expo, хотя его scripts dev/build/preview остаются Vite-командами.
  if grep -Eq '"vite"[[:space:]]*:' "$package_file"; then
    echo "vite"
  elif grep -Eq '"expo"[[:space:]]*:' "$package_file"; then
    echo "expo"
  else
    echo "npm"
  fi
}

human_type() {
  case "$1" in
    expo) echo "Expo" ;;
    vite) echo "Vite" ;;
    spring) echo "Spring Boot" ;;
    npm) echo "npm (неизвестный тип)" ;;
    maven) echo "Maven (не Spring Boot)" ;;
    *) echo "$1" ;;
  esac
}

project_dirs=()
project_types=()
project_labels=()
project_markers=()
project_task_numbers=()

task_number_for_project() {
  local label="$1"
  local type="$2"
  local number

  local task_pattern="/0*([0-9]+)[[:space:]_-]"
  if [[ "/$label" =~ $task_pattern ]]; then
    number=$((10#${BASH_REMATCH[1]}))
    echo "$number"
  elif [[ "$type" == "spring" && "$label" == "projects/spring-boot/bookstore" ]]; then
    # В комплекте общий Spring-проект хранится как projects/spring-boot/bookstore.
    echo "3"
  else
    echo "0"
  fi
}

is_supported_type() {
  case "$1" in
    vite|expo|spring) return 0 ;;
    *) return 1 ;;
  esac
}

has_supported_ancestor() {
  local project_dir="$1"
  local ancestor
  local ancestor_type

  ancestor="$(dirname -- "$project_dir")"
  while [[ "$ancestor" == "$root_dir" || "$ancestor" == "$root_dir/"* ]]; do
    ancestor_type=""
    if [[ -f "$ancestor/package.json" ]]; then
      ancestor_type="$(package_type "$ancestor/package.json")"
    elif [[ -f "$ancestor/pom.xml" ]] && grep -Eq 'spring-boot' "$ancestor/pom.xml"; then
      ancestor_type="spring"
    fi

    if [[ -n "$ancestor_type" ]] && is_supported_type "$ancestor_type"; then
      return 0
    fi

    [[ "$ancestor" != "$root_dir" ]] || break
    ancestor="$(dirname -- "$ancestor")"
  done
  return 1
}

while IFS= read -r marker; do
  [[ -n "$marker" ]] || continue

  project_dir="$(dirname -- "$marker")"
  relative_path="${project_dir#"$root_dir"/}"
  if [[ "$relative_path" == "$project_dir" ]]; then
    relative_path="$(basename -- "$project_dir")"
  fi

  if [[ "$(basename -- "$marker")" == "package.json" ]]; then
    detected_type="$(package_type "$marker")"
  elif grep -Eq 'spring-boot' "$marker"; then
    detected_type="spring"
  else
    detected_type="maven"
  fi

  # Не показываем неподдерживаемый npm/Maven-проект как запускаемое приложение.
  is_supported_type "$detected_type" || continue

  # Если проект уже имеет запускаемый корень, вложенные package.json/pom.xml
  # считаются его внутренними частями, а не отдельными приложениями.
  has_supported_ancestor "$project_dir" && continue

  task_number="$(task_number_for_project "$relative_path" "$detected_type")"

  project_dirs+=("$project_dir")
  project_types+=("$detected_type")
  project_labels+=("$relative_path")
  project_markers+=("$marker")
  project_task_numbers+=("$task_number")
done < <(
  find "$root_dir" \
    \( -type d \( \
      -name .git -o \
      -name node_modules -o \
      -name .expo -o \
      -name dist -o \
      -name build -o \
      -name target -o \
      -name coverage \
    \) -prune \) -o \
    \( -type f \( -name package.json -o -name pom.xml \) -print \) \
    | LC_ALL=C sort
)

[[ ${#project_dirs[@]} -gt 0 ]] || die "в '$root_dir' не найдено ни одного package.json или pom.xml."

# Один физический каталог — одно приложение: этапы не дублируются.

project_sort_key() {
  local task_number="$1"
  local label="$2"
  if ((task_number <= 0)); then
    task_number=99999999
  fi
  printf '%08d|%s' "$task_number" "$label"
}

# Сортируем по логическому номеру работы: 01-09.
for ((left = 0; left < ${#project_dirs[@]}; left++)); do
  for ((right = left + 1; right < ${#project_dirs[@]}; right++)); do
    left_key="$(project_sort_key "${project_task_numbers[$left]}" "${project_labels[$left]}")"
    right_key="$(project_sort_key "${project_task_numbers[$right]}" "${project_labels[$right]}")"
    if [[ "$left_key" > "$right_key" ]]; then
      temporary="${project_dirs[$left]}"
      project_dirs[$left]="${project_dirs[$right]}"
      project_dirs[$right]="$temporary"

      temporary="${project_types[$left]}"
      project_types[$left]="${project_types[$right]}"
      project_types[$right]="$temporary"

      temporary="${project_labels[$left]}"
      project_labels[$left]="${project_labels[$right]}"
      project_labels[$right]="$temporary"

      temporary="${project_markers[$left]}"
      project_markers[$left]="${project_markers[$right]}"
      project_markers[$right]="$temporary"

      temporary="${project_task_numbers[$left]}"
      project_task_numbers[$left]="${project_task_numbers[$right]}"
      project_task_numbers[$right]="$temporary"
    fi
  done
done

print_projects() {
  local index

  echo "Найденные проекты:"
  echo
  for ((index = 0; index < ${#project_dirs[@]}; index++)); do
    printf '%2d) %-24s %s\n' \
      "$((index + 1))" \
      "[$(human_type "${project_types[$index]}")]" \
      "${project_labels[$index]}"
  done
}

if [[ $list_only -eq 1 ]]; then
  print_projects
  exit 0
fi

selected_indices=()

add_selected_index() {
  local candidate="$1"
  local existing

  for existing in "${selected_indices[@]}"; do
    [[ "$existing" != "$candidate" ]] || return 0
  done
  selected_indices+=("$candidate")
}

select_from_numbers() {
  local input="${1//,/ }"
  local token
  local number

  for token in $input; do
    if [[ "$token" == "all" || "$token" == "все" ]]; then
      for ((number = 0; number < ${#project_dirs[@]}; number++)); do
        add_selected_index "$number"
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      number=$((10#$token))
      if ((number < 1 || number > ${#project_dirs[@]})); then
        die "номера проекта $token нет; допустимы номера от 1 до ${#project_dirs[@]}."
      fi
      add_selected_index "$((number - 1))"
    else
      die "'$token' не является номером проекта."
    fi
  done
}

select_from_path() {
  local requested="$1"
  local requested_dir
  local index
  local match=-1
  local match_count=0
  local explicit_marker
  local explicit_type

  if [[ -d "$requested" ]]; then
    requested_dir="$(cd -- "$requested" && pwd)"
  elif [[ -d "$root_dir/$requested" ]]; then
    requested_dir="$(cd -- "$root_dir/$requested" && pwd)"
  else
    die "папка проекта не существует: $requested"
  fi

  for ((index = 0; index < ${#project_dirs[@]}; index++)); do
    if [[ "${project_dirs[$index]}" == "$requested_dir" || "${project_dirs[$index]}" == "$requested_dir/"* ]]; then
      match="$index"
      match_count=$((match_count + 1))
    fi
  done

  # Явно выбранный вложенный stage разрешён, даже если primary уже найден.
  if [[ $match_count -eq 0 && ( "$requested_dir" == "$root_dir" || "$requested_dir" == "$root_dir/"* ) ]]; then
    explicit_marker=""
    explicit_type=""
    if [[ -f "$requested_dir/package.json" ]]; then
      explicit_marker="$requested_dir/package.json"
      explicit_type="$(package_type "$explicit_marker")"
    elif [[ -f "$requested_dir/pom.xml" ]] && grep -Eq 'spring-boot' "$requested_dir/pom.xml"; then
      explicit_marker="$requested_dir/pom.xml"
      explicit_type="spring"
    fi
    if is_supported_type "$explicit_type"; then
      match="${#project_dirs[@]}"
      project_dirs+=("$requested_dir")
      project_types+=("$explicit_type")
      project_labels+=("${requested_dir#"$root_dir"/}")
      project_markers+=("$explicit_marker")
      project_task_numbers+=("0")
      match_count=1
    fi
  fi

  if [[ $match_count -eq 0 ]]; then
    die "в '$requested' нет поддерживаемого файла проекта."
  elif [[ $match_count -gt 1 ]]; then
    die "в '$requested' найдено несколько проектов; укажите точнее или выберите их по номерам."
  fi

  add_selected_index "$match"
}

if [[ $select_all -eq 1 ]]; then
  for ((index = 0; index < ${#project_dirs[@]}; index++)); do
    add_selected_index "$index"
  done
elif [[ -n "$selection_spec" ]]; then
  select_from_numbers "$selection_spec"
elif [[ ${#project_requests[@]} -gt 0 ]]; then
  for requested_project in "${project_requests[@]}"; do
    select_from_path "$requested_project"
  done
else
  [[ -t 0 ]] || die "нет интерактивного ввода; используйте --all, --select или --project."
  print_projects
  echo
  echo "Введите номера через пробел/запятую, 'all' для всех или 0 для отмены."
  read -r -p "Ваш выбор: " selection_spec
  if [[ "$selection_spec" == "0" ]]; then
    echo "Запуск отменён."
    exit 0
  fi
  select_from_numbers "$selection_spec"
fi

[[ ${#selected_indices[@]} -gt 0 ]] || die "не выбран ни один проект."

echo "Выбрано работ: ${#selected_indices[@]}"
for selected_index in "${selected_indices[@]}"; do
  echo "  - ${project_labels[$selected_index]} ($(human_type "${project_types[$selected_index]}"))"
done

# Для каждого Expo-проекта выбираем платформу ДО сборки и запуска.
for selected_index in "${selected_indices[@]}"; do
  [[ "${project_types[$selected_index]}" == "expo" ]] || continue
  selected_platform="$expo_platform"
  if [[ -z "$selected_platform" ]]; then
    if [[ $dry_run -eq 1 ]]; then
      selected_platform="<ios|android|web>"
    elif [[ $build_only -eq 1 ]]; then
      selected_platform="android"
    elif [[ -t 0 ]]; then
      echo
      echo "Где открыть ${project_labels[$selected_index]}?"
      echo "1) iOS Simulator (Mac + Xcode)"
      echo "2) Android Emulator (Android Studio / SDK)"
      echo "3) Web (браузер, НЕ эмулятор телефона)"
      echo "0) Отмена"
      while true; do
        read -r -p "Режим: " platform_choice || die "ввод прерван."
        case "$platform_choice" in
          1|ios) selected_platform=ios; break ;;
          2|android) selected_platform=android; break ;;
          3|web) selected_platform=web; break ;;
          0) echo "Запуск отменён."; exit 0 ;;
          *) echo "Введите 1, 2, 3 или 0." ;;
        esac
      done
    else
      die "для Expo укажите --expo-platform ios, android или web."
    fi
  fi
  project_expo_platforms[$selected_index]="$selected_platform"
done

print_dry_run_plan() {
  local index="$1"
  local type="${project_types[$index]}"

  echo
  echo "План: ${project_labels[$index]}"
  case "$type" in
    vite)
      echo "  зависимости: npm ci --engine-strict (или npm install --engine-strict без lock)"
      echo "  проверка:     typecheck при наличии; test:run или CI=1 npm test"
      echo "  сборка:       npm run build"
      echo "  запуск:       npm exec -- vite preview --host 127.0.0.1 --port <свободный> --strictPort"
      ;;
    expo)
      echo "  зависимости: npm ci --engine-strict (или npm install --engine-strict без lock)"
      echo "  проверка:     typecheck при наличии; test:run или CI=1 npm test; Expo Doctor"
      echo "  сборка:       expo export --platform ${project_expo_platforms[$index]} --output-dir dist"
      echo "  запуск:       expo start --${project_expo_platforms[$index]} --localhost --port <свободный>"
      echo "  используется локальный Expo CLI; --no-open отключает открытие среды."
      ;;
    spring)
      echo "  сборка:       bash ./mvnw clean verify"
      echo "  запуск:       java -jar target/<приложение>.jar --server.port=<свободный>"
      ;;
    *)
      echo "  ошибка: тип проекта не поддерживается"
      ;;
  esac
}

if [[ $dry_run -eq 1 ]]; then
  for selected_index in "${selected_indices[@]}"; do
    print_dry_run_plan "$selected_index"
  done
  if [[ $build_only -eq 1 ]]; then
    echo
    echo "Режим --build-only: команды запуска были бы пропущены."
  fi
  exit 0
fi

need_node=0
need_java=0
for selected_index in "${selected_indices[@]}"; do
  case "${project_types[$selected_index]}" in
    vite|expo|npm) need_node=1 ;;
    spring|maven) need_java=1 ;;
  esac
done

if [[ $need_node -eq 1 ]] && { ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; }; then
  export NVM_DIR="${NVM_DIR:-${HOME:-}/.nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
  fi
fi

# Не включаем `set -u`: стандартный macOS Bash 3.2 считает пустые массивы
# (например, список уже занятых нами портов до первого запуска) необъявленными.

if [[ $need_node -eq 1 ]]; then
  command -v node >/dev/null 2>&1 || die "Node.js не найден. Установите актуальную LTS-версию Node.js."
  command -v npm >/dev/null 2>&1 || die "npm не найден. Переустановите Node.js вместе с npm."

  if ! node -e '
const [major, minor, patch] = process.versions.node.split(".").map(Number);
const supported =
  major > 22 ||
  (major === 22 && minor >= 12) ||
  (major === 20 && (minor > 19 || (minor === 19 && patch >= 4)));
if (!supported) {
  console.error(`Требуется Node.js 20.19.4+ или 22.12+; установлена ${process.versions.node}.`);
  process.exit(1);
}
'; then
    echo "Если используется NVM: nvm install 22 && nvm use 22" >&2
    exit 1
  fi
fi

if [[ $need_java -eq 1 ]]; then
  command -v java >/dev/null 2>&1 || die "Java не найдена; для Spring Boot установите JDK 17 или новее."
  java_major="$(java -XshowSettings:properties -version 2>&1 | awk '/java.version =/ { split($3, parts, "."); if (parts[1] == 1) print parts[2]; else print parts[1]; exit }')"
  [[ "$java_major" =~ ^[0-9]+$ ]] || die "не удалось определить версию Java."
  ((java_major >= 17)) || die "для Spring Boot требуется JDK 17 или новее; найдена Java $java_major."
fi

validate_package_json() {
  local package_file="$1"
  node -e '
const fs = require("fs");
const file = process.argv[1];
const value = JSON.parse(fs.readFileSync(file, "utf8"));
if (!value || typeof value !== "object" || Array.isArray(value)) {
  throw new Error("корень package.json должен быть объектом");
}
' "$package_file" >/dev/null
}

has_npm_script() {
  local package_file="$1"
  local script_name="$2"
  node -e '
const value = require(process.argv[1]);
process.exit(value.scripts && typeof value.scripts[process.argv[2]] === "string" ? 0 : 1);
' "$package_file" "$script_name"
}

validate_selected_projects() {
  local index
  local type
  local marker
  local dir

  for index in "${selected_indices[@]}"; do
    type="${project_types[$index]}"
    marker="${project_markers[$index]}"
    dir="${project_dirs[$index]}"

    [[ -f "$marker" ]] || die "файл проекта исчез: $marker"

    case "$type" in
      vite|expo|npm)
        if ! validate_package_json "$marker"; then
          die "некорректный JSON в $marker"
        fi
        if [[ "$type" == "vite" ]] && ! has_npm_script "$marker" "build"; then
          die "в $marker отсутствует script 'build'."
        fi
        # Expo вызывается напрямую: scripts start/web не обязательны.
        if [[ "$type" == "npm" ]]; then
          die "не удалось определить Vite или Expo в $dir; этот npm-проект не запускается автоматически."
        fi
        ;;
      spring)
        if [[ ! -f "$dir/mvnw" ]] && ! command -v mvn >/dev/null 2>&1; then
          die "для $dir не найден Maven Wrapper (mvnw) и команда mvn."
        fi
        ;;
      maven)
        die "$dir является Maven-проектом, но не распознан как Spring Boot."
        ;;
    esac
  done
}

validate_selected_projects
if [[ $build_only -eq 0 ]]; then
  command -v curl >/dev/null 2>&1 || die "curl нужен для проверки HTTP-готовности серверов."
fi

expo_cli_for() {
  node -e '
const path = require("path");
const p = require.resolve("expo/package.json", {paths:[process.argv[1]]});
const pkg = require(p);
const bin = typeof pkg.bin === "string" ? pkg.bin : pkg.bin.expo;
process.stdout.write(path.resolve(path.dirname(p), bin));
' "$1"
}

validate_expo_device() {
  local platform="$1"
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  local devices
  local avds
  [[ $build_only -eq 0 && $no_open -eq 0 ]] || return 0
  case "$platform" in
    ios)
      [[ "$(uname -s)" == "Darwin" ]] || die "iOS Simulator доступен только в macOS. Выберите android или web."
      command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1 || die "нужен полный Xcode (не только Command Line Tools). Откройте Xcode и завершите первичную настройку."
      if ! devices="$(xcrun simctl list devices available --json)"; then
        die "не удалось получить симуляторы Xcode; проверьте выбранный Xcode и установленную платформу iOS."
      fi
      if ! printf '%s' "$devices" | node -e '
let s=""; process.stdin.on("data",c=>s+=c); process.stdin.on("end",()=>{
const d=JSON.parse(s).devices || {};
process.exit(Object.keys(d).some(k=>k.includes(".iOS-") && d[k].some(v=>v.isAvailable!==false))?0:1);
});'; then
        die "нет доступного iOS Simulator. Xcode → Settings → Components/Platforms → установите iOS и создайте симулятор."
      fi
      ;;
    android)
      if [[ -z "$sdk" ]]; then
        if [[ -d "${HOME:-}/Library/Android/sdk" ]]; then sdk="${HOME:-}/Library/Android/sdk"
        elif [[ -d "${HOME:-}/Android/Sdk" ]]; then sdk="${HOME:-}/Android/Sdk"; fi
      fi
      if [[ -n "$sdk" && -d "$sdk" ]]; then
        export ANDROID_HOME="$sdk"
        export PATH="$sdk/platform-tools:$sdk/emulator:$PATH"
      fi
      command -v adb >/dev/null 2>&1 || die "Android SDK: adb не найден. Установите Android Studio + SDK Platform-Tools; проверьте ANDROID_HOME."
      devices="$(adb devices)" || die "Android: adb не отвечает."
      if ! printf '%s\n' "$devices" | grep -Eq '^emulator-[0-9]+[[:space:]]+device'; then
        command -v emulator >/dev/null 2>&1 || die "Android Emulator не найден. Установите его через SDK Manager."
        avds="$(emulator -list-avds)" || die "не удалось прочитать Android AVD."
        [[ -n "$avds" ]] || die "нет Android AVD. Android Studio → Device Manager → Create Virtual Device."
      fi
      echo "Expo откроет доступное Android-устройство/AVD. Если подключён телефон, отключите его для запуска именно эмулятора."
      ;;
  esac
}

# Проверяем среду раньше длительной сборки. Ничего не устанавливаем глобально.
for selected_index in "${selected_indices[@]}"; do
  [[ "${project_types[$selected_index]}" == "expo" ]] || continue
  validate_expo_device "${project_expo_platforms[$selected_index]}"
done

prepare_expo_platform() {
  local dir="$1"
  local platform="$2"
  local cli
  local missing
  local answer
  local config
  cli="$(expo_cli_for "$dir")" || die "локальный Expo CLI не найден в $dir."
  if [[ "$platform" == "web" ]]; then
    missing="$(node -e '
const p=require(process.argv[1]); const d={...p.dependencies,...p.devDependencies};
console.log(["react-dom","react-native-web","@expo/metro-runtime"].filter(n=>!d[n]).join(" "));
' "$dir/package.json")"
    if [[ -n "$missing" ]]; then
      echo "Для Web отсутствуют зависимости: $missing"
      if [[ $install_web_deps -ne 1 ]]; then
        if [[ -t 0 ]]; then
          read -r -p "Установить совместимые с Expo версии в этот проект? [y/N]: " answer || die "ввод прерван."
          case "$answer" in y|Y|yes|да|Да) ;; *) die "выберите native-режим или установите зависимости: npx expo install $missing" ;; esac
        else
          die "повторите с --install-web-deps либо выполните в проекте: npx expo install $missing"
        fi
      fi
      # Список фиксированный, пользовательский ввод в shell-команду не подставляется.
      node "$cli" install react-dom react-native-web @expo/metro-runtime
    fi
  fi
  config="$(node "$cli" config --type public --json)" || die "не удалось прочитать конфигурацию Expo: $dir"
  if ! printf '%s' "$config" | node -e '
let s=""; process.stdin.on("data",c=>s+=c); process.stdin.on("end",()=>{
const c=JSON.parse(s); const p=c.platforms || (c.expo && c.expo.platforms);
process.exit(!Array.isArray(p) || p.includes(process.argv[1]) ? 0 : 1);
});' "$platform"; then
    die "платформа $platform исключена настройкой platforms в app.json/app.config.*. Добавьте её в список platforms или выберите другой режим. Конфигурация не изменена."
  fi
}

install_node_dependencies() {
  local dir="$1"
  local install_stamp="$dir/node_modules/.package-lock.json"

  cd "$dir"
  if [[ ! -f package-lock.json ]]; then
    echo "package-lock.json отсутствует — выполняю npm install."
    npm install --engine-strict
  elif [[ ! -d node_modules || ! -f "$install_stamp" || package.json -nt "$install_stamp" || package-lock.json -nt "$install_stamp" ]]; then
    echo "Устанавливаю точные версии зависимостей командой npm ci."
    if ! npm ci --engine-strict; then
      echo "Ошибка npm ci обычно означает, что package.json и package-lock.json не согласованы." >&2
      echo "Исправьте lock-файл командой npm install, затем повторите запуск." >&2
      return 1
    fi
  else
    echo "Зависимости уже установлены и актуальны."
  fi
}

has_typescript_sources() {
  local dir="$1"
  local source_file

  source_file="$(
    find "$dir" \
      \( -type d \( -name node_modules -o -name .expo -o -name dist -o -name coverage \) -prune \) -o \
      \( -type f \( -name '*.ts' -o -name '*.tsx' \) -print \) \
      | sed -n '1p'
  )"
  [[ -n "$source_file" ]]
}

run_node_checks() {
  local dir="$1"
  local type="$2"
  local package_file="$dir/package.json"

  cd "$dir"
  if has_npm_script "$package_file" "typecheck"; then
    echo "Проверяю TypeScript..."
    npm run typecheck
  elif [[ -f tsconfig.json && -x node_modules/.bin/tsc ]]; then
    echo "Проверяю TypeScript..."
    npm exec -- tsc --noEmit
  elif has_typescript_sources "$dir"; then
    warn "в ${project_labels[$3]} есть TypeScript, но не настроена команда typecheck."
  fi

  if [[ $skip_tests -eq 1 ]]; then
    echo "Тесты пропущены по параметру --skip-tests."
  elif has_npm_script "$package_file" "test:run"; then
    echo "Запускаю тесты..."
    npm run test:run
  elif has_npm_script "$package_file" "test"; then
    echo "Запускаю тесты..."
    # Honor the configured runner. Jest flags break Node --test, while
    # --run is not a universal option. CI also disables default watch mode.
    CI=1 npm test
  else
    warn "для ${project_labels[$3]} не настроены автоматические тесты."
  fi
}

build_node_project() {
  local index="$1"
  local dir="${project_dirs[$index]}"
  local type="${project_types[$index]}"

  echo
  echo "============================================================"
  echo "Проверяю и собираю: ${project_labels[$index]}"
  echo "============================================================"

  install_node_dependencies "$dir"
  if [[ "$type" == "expo" ]]; then
    prepare_expo_platform "$dir" "${project_expo_platforms[$index]}"
  fi
  run_node_checks "$dir" "$type" "$index"

  cd "$dir"
  if [[ "$type" == "vite" ]]; then
    echo "Собираю Vite production-версию..."
    npm run build
    [[ -s dist/index.html ]] || die "Vite не создал $dir/dist/index.html"
  else
    echo "Проверяю совместимость Expo..."
    npx --yes expo-doctor@latest
    echo "Собираю Expo bundle: ${project_expo_platforms[$index]}..."
    node "$(expo_cli_for "$dir")" export --platform "${project_expo_platforms[$index]}" --output-dir dist
    [[ -n "$(find dist -type f -print | sed -n '1p')" ]] || die "Expo не создал файлы в $dir/dist"
  fi
}

validate_mysql_profile() {
  local dir="$1"
  local profile="$dir/src/main/resources/application-mysql.properties"

  [[ -f "$profile" ]] || die "для работы 09 отсутствует $profile"
  grep -F '${BOOKSTORE_MYSQL_URL}' "$profile" >/dev/null || die "MySQL URL должен приходить из BOOKSTORE_MYSQL_URL."
  grep -F '${BOOKSTORE_MYSQL_USERNAME}' "$profile" >/dev/null || die "MySQL username должен приходить из BOOKSTORE_MYSQL_USERNAME."
  grep -F '${BOOKSTORE_DB_PASSWORD}' "$profile" >/dev/null || die "MySQL password должен приходить из BOOKSTORE_DB_PASSWORD."
}

run_maven() {
  local dir="$1"
  shift

  cd "$dir"
  if [[ -f mvnw ]]; then
    bash ./mvnw "$@"
  else
    mvn "$@"
  fi
}

build_spring_project() {
  local index="$1"
  local dir="${project_dirs[$index]}"

  echo
  echo "============================================================"
  echo "Проверяю и собираю: ${project_labels[$index]}"
  echo "============================================================"

  if [[ $skip_tests -eq 1 ]]; then
    run_maven "$dir" -DskipTests clean verify
  else
    run_maven "$dir" clean verify
  fi
}

processed_build_dirs=()

build_dir_was_processed() {
  local candidate="$1"
  local existing
  for existing in "${processed_build_dirs[@]}"; do
    [[ "$existing" != "$candidate" ]] || return 0
  done
  return 1
}

for selected_index in "${selected_indices[@]}"; do
  if [[ "${project_labels[$selected_index]}" == *"[MySQL Optional]" ]]; then
    validate_mysql_profile "${project_dirs[$selected_index]}"
  fi

  if build_dir_was_processed "${project_dirs[$selected_index]}"; then
    echo "Пропускаю повторную сборку общего каталога: ${project_labels[$selected_index]}"
    continue
  fi
  processed_build_dirs+=("${project_dirs[$selected_index]}")

  case "${project_types[$selected_index]}" in
    vite|expo) build_node_project "$selected_index" ;;
    spring) build_spring_project "$selected_index" ;;
  esac
done

echo
echo "Сборки завершены; отсутствующие или пропущенные тесты указаны выше."

if [[ $build_only -eq 1 ]]; then
  exit 0
fi

reserved_ports=()

port_is_reserved() {
  local candidate="$1"
  local reserved
  for reserved in "${reserved_ports[@]}"; do
    [[ "$reserved" != "$candidate" ]] || return 0
  done
  return 1
}

port_is_free() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v nc >/dev/null 2>&1; then
    ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1
  else
    ! (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
  fi
}

choose_port() {
  local candidate="$1"
  local limit=$((candidate + 200))

  while ((candidate <= limit)); do
    if ! port_is_reserved "$candidate" && port_is_free "$candidate"; then
      reserved_ports+=("$candidate")
      chosen_port="$candidate"
      return 0
    fi
    candidate=$((candidate + 1))
  done

  die "не найден свободный порт в диапазоне $1-$limit."
}

spring_jar() {
  local dir="$1"
  local jar
  local selected=""
  local count=0

  for jar in "$dir"/target/*.jar; do
    [[ -f "$jar" ]] || continue
    case "$(basename -- "$jar")" in
      original-*|*-sources.jar|*-javadoc.jar|*-tests.jar|*-test.jar|*-plain.jar) continue ;;
    esac
    selected="$jar"
    count=$((count + 1))
  done
  if [[ $count -eq 0 ]]; then
    echo "В $dir/target нет JAR приложения после сборки." >&2
    return 1
  fi
  if [[ $count -ne 1 ]]; then
    echo "В $dir/target найдено несколько JAR приложения. Запуск отменён: выбирать первый небезопасно." >&2
    echo "Проверьте настройки Maven/classifier: после clean verify должен остаться один запускаемый JAR." >&2
    return 1
  fi
  printf '%s\n' "$selected"
}

spring_url_path() {
  local dir="$1"
  local login_path
  if [[ -n "$spring_ready_path" ]]; then
    echo "$spring_ready_path"
    return
  fi
  # A literal endpoint, never shell code. CLI override has higher priority.
  if [[ -f "$dir/.spring-ready-path" ]]; then
    login_path="$(cat "$dir/.spring-ready-path")"
    if [[ "$login_path" == /* && "$login_path" != //* && "$login_path" != *$'\n'* && "$login_path" != *$'\r'* && ${#login_path} -le 4096 ]]; then
      printf '%s\n' "$login_path"
      return
    fi
    echo "Некорректный .spring-ready-path: нужен один относительный URL, начинающийся с /." >&2
    return 1
  fi
  # Use a declared form-login page. A JWT/API SecurityFilterChain alone does
  # not imply a /login endpoint. Custom endpoints can be supplied explicitly.
  if [[ -d "$dir/src/main" ]]; then
    login_path="$(find "$dir/src/main" -type f -name '*.java' -exec sed -nE 's/.*[.]loginPage[[:space:]]*\([[:space:]]*"(\/[^"[:space:]]*)".*/\1/p' {} \; | LC_ALL=C sort -u)"
    if [[ -n "$login_path" && "$login_path" != *$'\n'* && "$login_path" != //* ]]; then
      printf '%s\n' "$login_path"
      return
    elif [[ -n "$login_path" ]]; then
      echo "Объявлено несколько loginPage; укажите --spring-ready-path." >&2
      return 1
    fi
  fi
  if [[ -d "$dir/src/main" ]] && grep -R -Eq '[.]formLogin[[:space:]]*\(' "$dir/src/main" 2>/dev/null; then
    echo "/login"
  elif [[ -d "$dir/src/main" ]] && grep -R -q '@GetMapping("/booklist")' "$dir/src/main" 2>/dev/null; then
    echo "/booklist"
  else
    echo "/"
  fi
}

launch_ports=()
launch_urls=()
launch_pids=()
launch_logs=()
launch_indices=()
launch_modes=()
started_dirs=()
logs_dir="$(mktemp -d "${TMPDIR:-/tmp}/homework-runner.XXXXXX")"

dir_was_started() {
  local candidate="$1"
  local existing
  for existing in "${started_dirs[@]}"; do
    [[ "$existing" != "$candidate" ]] || return 0
  done
  return 1
}

start_project() {
  local index="$1"
  local port="$2"
  local log_file="$3"
  local dir="${project_dirs[$index]}"
  local type="${project_types[$index]}"
  local jar
  local cli
  local args=()

  case "$type" in
    vite)
      (
        cd "$dir"
        exec npm exec -- vite preview --host 127.0.0.1 --port "$port" --strictPort
      ) >"$log_file" 2>&1 &
      ;;
    expo)
      cli="$(expo_cli_for "$dir")" || die "не найден Expo CLI."
      args=(start --localhost --port "$port")
      if [[ "${project_expo_platforms[$index]}" == "web" ]]; then
        args+=(--web)
      else
        args+=(--go)
        if [[ $no_open -eq 0 ]]; then args+=("--${project_expo_platforms[$index]}"); fi
      fi
      (
        cd "$dir"
        export BROWSER=none
        exec node "$cli" "${args[@]}"
      ) < /dev/null >"$log_file" 2>&1 &
      ;;
    spring)
      jar="$(spring_jar "$dir")" || die "не удалось однозначно выбрать JAR для $dir."
      echo "Запускаю JAR: $jar"
      (
        cd "$dir"
        exec java -jar "$jar" --server.port="$port"
      ) >"$log_file" 2>&1 &
      ;;
  esac

  launch_pids+=("$!")
}

# Bash job control даёт каждому запущенному серверу СОБСТВЕННУЮ группу.
# Завершаем только эти группы: без pkill node, удаления файлов и убийства по порту.
set -m
cleanup_servers() {
  local exit_status=$?
  local pid
  local attempt=0
  local alive
  trap - EXIT
  trap '' INT TERM
  for pid in "${launch_pids[@]}"; do
    kill -TERM -- "-$pid" >/dev/null 2>&1 || true
  done
  while ((attempt < 5)); do
    alive=0
    for pid in "${launch_pids[@]}"; do
      if kill -0 -- "-$pid" >/dev/null 2>&1; then alive=1; fi
    done
    [[ $alive -eq 1 ]] || break
    sleep 1
    attempt=$((attempt + 1))
  done
  for pid in "${launch_pids[@]}"; do
    kill -KILL -- "-$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  done
  echo "Серверы этого запуска остановлены. Файлы проектов сохранены."
  exit "$exit_status"
}
trap cleanup_servers EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for selected_index in "${selected_indices[@]}"; do
  if dir_was_started "${project_dirs[$selected_index]}"; then
    echo "Один сервер уже представляет общий каталог: ${project_labels[$selected_index]}"
    continue
  fi
  started_dirs+=("${project_dirs[$selected_index]}")

  case "${project_types[$selected_index]}" in
    vite)
      choose_port 4173
      port="$chosen_port"
      url="http://127.0.0.1:$port/"
      ;;
    expo)
      choose_port 8081
      port="$chosen_port"
      url="http://127.0.0.1:$port/"
      ;;
    spring)
      choose_port 8080
      port="$chosen_port"
      url="http://127.0.0.1:$port$(spring_url_path "${project_dirs[$selected_index]}")"
      ;;
  esac

  log_file="$logs_dir/project-$((selected_index + 1)).log"
  launch_ports+=("$port")
  launch_urls+=("$url")
  launch_logs+=("$log_file")
  launch_indices+=("$selected_index")
  launch_modes+=("${project_expo_platforms[$selected_index]:-web}")
  start_project "$selected_index" "$port" "$log_file"
done

wait_until_ready() {
  local pid="$1"
  local url="$2"
  local log_file="$3"
  local mode="$4"
  local type="${5:-node}"
  local attempt=0
  local body
  local status
  local ready_url="$url"

  if [[ "$mode" != "web" ]]; then ready_url="${url}status"; fi

  while ((attempt < ready_timeout)); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "Сервер завершился до запуска. Последние строки журнала:" >&2
      tail -n 30 "$log_file" >&2 || true
      return 1
    fi
    if [[ "$type" == "spring" ]]; then
      # Публичный /login обязан отвечать 2xx. Защищённый 401/403 не подтверждает готовность.
      if status="$(curl -sS --max-time 2 --output /dev/null --write-out '%{http_code}' "$ready_url" 2>/dev/null)"; then
        case "$status" in
          2??) return 0 ;;
        esac
      fi
    elif body="$(curl -fsS --max-time 2 "$ready_url" 2>/dev/null)"; then
      if [[ "$mode" == "web" ]]; then return 0; fi
      if [[ "$body" == "packager-status:running" ]]; then
        # В SDK 54 эта строка печатается после попытки открытия среды.
        # Один HTTP-ответ Metro ещё не означает завершение установки Expo Go.
        if [[ $no_open -eq 1 ]] || grep -q 'Waiting on ' "$log_file"; then return 0; fi
      fi
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  echo "Сервер не подтвердил HTTP-готовность за $ready_timeout секунд: $ready_url" >&2
  tail -n 30 "$log_file" >&2 || true
  if [[ "$type" == "expo" ]]; then
    echo "Если Expo Go требует подтверждения установки/смены версии, запустите один раз вручную в папке проекта: npx expo start --$mode" >&2
  fi
  return 1
}

open_url() {
  local url="$1"

  if [[ $no_open -eq 1 ]]; then
    return 0
  elif command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || warn "не удалось открыть браузер: $url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || warn "не удалось открыть браузер: $url"
  else
    warn "команда открытия браузера не найдена; откройте вручную: $url"
  fi
}

echo
echo "Жду готовности серверов..."
for ((position = 0; position < ${#launch_pids[@]}; position++)); do
  selected_index="${launch_indices[$position]}"
  echo "Проверяю адрес: ${launch_urls[$position]}"
  echo "Журнал запуска: ${launch_logs[$position]}"
  wait_until_ready \
    "${launch_pids[$position]}" \
    "${launch_urls[$position]}" \
    "${launch_logs[$position]}" \
    "${launch_modes[$position]}" \
    "${project_types[$selected_index]}"
  if [[ "${launch_modes[$position]}" == "web" ]]; then
    open_url "${launch_urls[$position]}"
  else
    echo "Expo ${launch_modes[$position]}: Metro готов. Адрес ниже — сервер, НЕ страница приложения."
    [[ $no_open -eq 0 ]] || echo "Открытие эмулятора отключено (--no-open)."
  fi
done

echo
printf '%-4s %-18s %-9s %-7s %s\n' "№" "Тип" "Режим" "Порт" "Адрес сервера"
printf '%-4s %-18s %-9s %-7s %s\n' "--" "------------------" "---------" "-------" "--------------"
for ((position = 0; position < ${#launch_pids[@]}; position++)); do
  selected_index="${launch_indices[$position]}"
  printf '%-4d %-18s %-9s %-7s %s\n' \
    "$((selected_index + 1))" \
    "$(human_type "${project_types[$selected_index]}")" \
    "${launch_modes[$position]}" \
    "${launch_ports[$position]}" \
    "${launch_urls[$position]}"
done

echo
echo "HTTP-готовность серверов подтверждена. Журналы: $logs_dir"
if [[ $smoke_test -eq 1 ]]; then
  echo "Smoke-проверка завершена; серверы будут остановлены."
  exit 0
fi
echo "Для остановки нажмите Control + C."

while true; do
  for ((position = 0; position < ${#launch_pids[@]}; position++)); do
    pid="${launch_pids[$position]}"
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "Сервер ${project_labels[${launch_indices[$position]}]} неожиданно завершился." >&2
      tail -n 30 "${launch_logs[$position]}" >&2 || true
      exit 1
    fi
  done
  sleep 2
done
