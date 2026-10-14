# 14 · Text to Speech — полный разбор, код и запуск

[Исходное условие](ASSIGNMENT.md) · [README проекта](PROJECT-README.md)

## 1. Сначала условие: что требуется

Пользователь вводит текст, выбирает **English / Finnish / Swedish через SegmentedControl**, а приложение произносит его средствами **Expo Speech**. На образце кнопка называется `SAY IT`.

Это синтез речи: язык задаёт произношение, **не переводит введённое предложение**. Микрофон, запись аудио, сервер и API-ключ не требуются. Кнопка `STOP`, валидация, безопасная замена предыдущей фразы и сообщения о состоянии — дополнения нашего решения, а не придуманные обязательные пункты.

Маршрут: распаковать → установить зависимости → найти действующий App → связать текст и выбранный язык → запускать речь только по кнопке → обработать завершение/ошибки/остановку → проверить три языка → продемонстрировать звук на устройстве.

## 2. Готовый проект и дерево файлов

Архив содержит `14-text-to-speech/speech-app`. Все исходники, lock-файл, проверки, условие и этот разбор внутри. Git-истории и удалённой привязки нет.

```text
14-text-to-speech/
  speech-app/
    App.tsx
    index.ts
    package.json
    package-lock.json
    app.json
    tsconfig.json
    src/
      speech.ts
      expoSpeech.ts
      LanguageSelector.tsx
    tests/speech.test.ts
    docs/ASSIGNMENT.md
    docs/MANUAL.md
    docs/SOURCE.png
    README.md
```

Разместить папку `14-text-to-speech` в `<локальный-путь>`. Проверить, что `package.json` находится в `HW.Group-2/14-text-to-speech/speech-app/`, а не на дополнительном уровне вложенности.

## 3. Установка и индивидуальный запуск на Mac

Это **Expo SDK 57 + React Native + TypeScript**, не Vite. Нужен **Node.js 24.x**:

```bash
node --version
cd <папка-этого-репозитория>
npm ci
npm run typecheck
npm test
npm run web
```

Для телефона/эмулятора:

```bash
npm start
# Или, на Mac с настроенным Xcode:
npm run ios
# Или, с настроенным Android Studio/SDK:
npm run android
```

В первом варианте открыть QR-код в Expo Go совместимого SDK. Подключить телефон к сети компьютера. Android/iOS-симулятор нужно установить и настроить отдельно; сборка проекта сама не устанавливает Xcode или Android Studio.

`npm ci` применим к этому архиву: lock-файл включён. Для нового проекта без lock-файла сначала выполнить `npm install`. При наличии NVM и несовместимом Node:

```bash
source "$HOME/.nvm/nvm.sh"
nvm install 24
nvm use 24
```

Повторить установку в папке приложения. Эти команды не устанавливают сам NVM.

### Запуск через общий скрипт в HW.Group-2

```bash
cd <папка-этого-репозитория>
bash ./build-and-run.sh --list
bash ./build-and-run.sh --project "14-text-to-speech/speech-app" --expo-platform web
```

Для телефона/эмулятора выбрать `ios` или `android` вместо `web`. Копия запускателя на Mac может быть старее: проверить `bash ./build-and-run.sh --help`. Если параметры неизвестны, индивидуальный запуск выше работает без общего скрипта. Номер проекта брать из свежего списка, порт/URL — из таблицы запускателя. Control+C останавливает сервер; исходники удалять не нужно.

## 4. Если создаём самостоятельно с нуля

В `create-project.sh` выбрать Expo / React Native / TypeScript, пустой шаблон без Router; назвать папку `speech-app` внутри `14-text-to-speech`. Для **того же SDK 57** разместить файлы ниже и выполнить:

```bash
npm install
npx expo install --check
```

Если добавляем возможность в свой существующий Expo-проект, зависимости устанавливаются под **его** SDK:

```bash
npx expo install expo-speech @react-native-segmented-control/segmented-control react-native-safe-area-context
```

Не переносить package.json SDK 57 в SDK 54 и не смешивать разные версии React Native. В готовом архиве web-зависимости `react-dom`, `react-native-web` и `@expo/metro-runtime` уже указаны. Коды языка, компоненты и контроллер описаны ниже; для другого SDK сверить API в его официальной документации.

## 5. Как текст доходит до голоса

1. `package.json` указывает `main: "index.ts"`, который регистрирует `App`.
2. Экран хранит `text` и `selectedIndex`; до кнопки никакая фраза не произносится.
3. `LanguageSelector` показывает настоящий SegmentedControl, не три самодельные кнопки.
4. `event.nativeEvent.selectedSegmentIndex` сообщает, какой сегмент выбрали.
5. При `SAY IT` контроллер проверяет `trim()`, индекс языка и длину текста.
6. Перед новой фразой он дожидается `Speech.stop()`, чтобы не накапливать очередь одинаковых фраз.
7. Адаптер вызывает `Speech.speak(text, { language, ...callbacks })`.
8. События начала, окончания, остановки и ошибки обновляют сообщение на экране.
9. `STOP` прерывает речь. При закрытии экрана подписка снимается, контроллер останавливает синтезатор.

### Выбор языка: одна таблица вместо нескольких состояний

| Индекс | Сегмент | Код | Текст для проверки |
|---|---|---|---|
| 0 | English | `en-US` | `Hello! How are you today?` |
| 1 | Finnish | `fi-FI` | `Hei! Mitä sinulle kuuluu?` |
| 2 | Swedish | `sv-SE` | `Hej! Hur mår du idag?` |

Коды — выбранные нами варианты английского/финского/шведского. `selectedIndex` определяет запись единственного массива `LANGUAGES`, поэтому название и код не расходятся. Выбор Finnish не переводит English: для проверки Finnish ввести финскую фразу. Доступные голоса и их качество зависят от ОС. [Expo Speech](https://docs.expo.dev/versions/latest/sdk/speech/).

## 6. Файлы, функции и причины выбора

| Элемент | Что делает | Почему нужен |
|---|---|---|
| `LANGUAGES as const` | Единый набор названий, кодов и примеров | TypeScript сохраняет точные значения, а не произвольную строку |
| `LanguageCode` | Объединение разрешённых кодов | Нельзя случайно передать неправильный код из таблицы |
| `languageFromIndex` | Проверяет индекс и возвращает язык | Не обращаемся к несуществующему сегменту |
| `speechInputLimit` | Берёт меньший предел приложения и движка | Очень длинные фразы могут быть не приняты ОС |
| `validateSpeechRequest` | Проверяет пустоту, индекс и длину | Ошибка ввода не запускает синтезатор |
| `SpeechAdapter` | Контракт `speak`, `stop`, максимальная длина | Логику можно тестировать, не включая реальный звук |
| `SpeechController.say` | Валидация → остановка → новая фраза | Не накапливает старые произнесения |
| `SpeechController.stop` | Управляет остановкой и сообщением | Ученик видит, что команда обработана |
| `SpeechController.subscribe` | Передаёт изменения состояния экрану | Контроллер не импортирует React, но UI получает события |
| `SpeechController.dispose` | Отписка/остановка после закрытия | Запоздавшее событие не меняет уже снятый экран |
| `generation`, `isCurrent` | Помечают актуальную команду | Старый `onDone` не должен завершить новую фразу |
| `queueForAdapter`, `WeakMap` | Общая очередь для контроллеров одного синтезатора | Cleanup старого экрана завершается до речи нового после повторного открытия |
| `enqueue` | Последовательно выполняет команды общей очереди | Поздняя остановка старой команды не отменяет новую речь |
| `expoSpeechAdapter` | Вызывает настоящий Expo Speech | Единственное место зависимости от системного движка |
| `Speech.speak` | Произносит текст | Требуется заданием; это не облачный сервис |
| `language`, `rate`, `pitch` | Язык, скорость и высота | Язык выбран пользователем, скорость/высота здесь обычные `1` |
| `onStart / onDone / onStopped / onError` | События движка | Состояние не остаётся «speaking» после окончания/сбоя |
| `LanguageSelector` | Связывает SegmentedControl с индексом | Отдельный небольшой компонент для объяснения props |
| `TextInput`, `onChangeText` | Управляемое поле ввода | Значение находится в состоянии React |
| `useEffect` | Создаёт подписку и очистку контроллера | Не читает текст автоматически и не запускает речь при вводе |
| `SafeAreaView`, `KeyboardAvoidingView` | Учитывают края экрана и клавиатуру | Поле и кнопки доступны на телефоне |
| `StyleSheet.create` | Стили React Native | HTML/CSS-файлы Vite здесь не используются |

### Зачем контроллер сложнее одного Speech.speak

Для самого простого примера достаточно передать текст в `Speech.speak`. В рабочем экране появляются повторные нажатия, отложенные `stop`, события старой фразы и уход с экрана. Поэтому команды выстроены последовательно, каждая имеет номер, а устаревшие события игнорируются. Это защита поведения, не обязательное требование преподавателя и не необходимость отдельного сервера.

Одна неверная попытка (например, пустой текст) не прерывает уже произносимую фразу. Новый корректный `SAY IT` заменяет её. Состояние `starting` означает подготовку, `speaking` — речь, `stopping` — выполнение остановки, `idle` — готовность, `error` — сбой. Успешное отправление команды движку не доказывает, что пользователь услышал звук: громкость и голоса проверяются отдельно.

## 7. Частые проблемы

| Симптом | Что проверить |
|---|---|
| `react/jsx-runtime` не найден | `npm ci` в самой `speech-app`, совместимый Node; редактор использует локальный TypeScript |
| `Cannot resolve entry file` | Существуют `index.ts` и `App.tsx`, `main` указывает на `index.ts` |
| Осталась стартовая страница другого шаблона | Редактируется действующий экран, не лишний `src/App.tsx` от Vite |
| Нет звука на физическом iPhone | Отключить беззвучный режим, проверить громкость и выбранный голос |
| Finnish звучит неправильно/голос отсутствует | Установить/настроить голос языка в ОС, проверить сам финский текст |
| В браузере речь не начинается | Нажать SAY IT пользователем; проверить поддержку/разрешения браузера и голос ОС |
| Native module отсутствует | Проверить SDK/Expo Go; для своего development build пересобрать бинарное приложение после установки библиотеки |
| Сегменты изменились, но речь старая | Изменение языка действует на следующую команду SAY IT; текущую остановить или заменить |

На физическом iPhone беззвучный режим может подавлять Expo Speech. Синтезатор не нуждается в разрешении на микрофон. Если нужен список голосов для диагностики, используется `Speech.getAvailableVoicesAsync()`; отдельный voice-picker не добавлен, потому что исходное условие требует выбор языка, а не голоса. [Speech API](https://docs.expo.dev/versions/latest/sdk/speech/), [SegmentedControl](https://docs.expo.dev/versions/latest/sdk/segmented-control/).

## 8. Автоматические и ручные проверки

```bash
npm run typecheck
npm test
npx expo install --check
npm run build
```

Тесты запускаются в Node: используются подставные `speak/stop`, а не настоящий динамик. Они проверяют входные значения, три кода, порядок вызовов, исключения, быструю замену команды, запоздалые события и закрытие контроллера. Экспорт Android/iOS/web проверяет сборку JavaScript, **не создаёт APK/IPA** и не доказывает произношение на Mac.

| Ручной шаг | Ожидаемый результат |
|---|---|
| Открыть приложение | Речь не запускается автоматически |
| Нажать SAY IT с пустотой/пробелами | Понятное сообщение, движок не запускается |
| English + английская фраза | Английское произношение |
| Finnish + финская фраза | Финское произношение при наличии голоса ОС |
| Swedish + шведская фраза | Шведское произношение при наличии голоса ОС |
| Нажать SAY IT снова | Новая фраза заменяет старую, очередь не копится |
| Нажать STOP | Речь останавливается, сообщение меняется |
| Уйти с экрана | Речь прекращается, события не обновляют снятый экран |
| Проверить узкий экран с клавиатурой | Поле, сегменты и кнопки доступны |

### Порядок объяснения ученице

Сначала показать связку `TextInput → text`, затем `SegmentedControl → selectedIndex → LANGUAGES`. Найти обработчик SAY IT в App и перейти к `SpeechController.say`: проверка, остановка, запуск. Отдельно объяснить callbacks и проблему старого `onDone`. Закончить адаптером, тестами и реальным прослушиванием трёх фраз.

На сдачу: TypeScript-исходники, конфигурация/lock-файл, README и демонстрация трёх языков. Не включать `node_modules` и `dist`. Дата/канал сдачи на скриншоте не указаны. Учебный дневник, если он понадобится в другой работе, заполняется реальными действиями ученицы, не вымышленной историей.

`package-lock.json` сформирован npm и входит в проект целиком; ниже не дублируется его большой список транзитивных зависимостей. Все написанные нами файлы кода, конфигурации и тестов приведены полностью.

## Полное содержимое файлов

Код ниже получен непосредственно из проверяемого проекта. Не нужно угадывать пропущенные строки или дописывать JSX. Создавайте файлы по указанным путям, относительно корня приложения.

### package.json

Совместимые зависимости Expo Speech и SegmentedControl, команды запуска и проверки.

```json
{
  "name": "assignment-14-text-to-speech",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "main": "index.ts",
  "engines": {
    "node": ">=24 <25"
  },
  "scripts": {
    "start": "expo start",
    "android": "expo start --android",
    "ios": "expo start --ios",
    "web": "expo start --web",
    "typecheck": "tsc --noEmit",
    "test": "node --experimental-strip-types --test tests/*.test.ts",
    "build": "expo export --platform all --output-dir dist",
    "bundle:android": "expo export --platform android --output-dir dist-android",
    "bundle:ios": "expo export --platform ios --output-dir dist-ios"
  },
  "dependencies": {
    "@expo/metro-runtime": "~57.0.16",
    "@react-native-segmented-control/segmented-control": "2.5.7",
    "expo": "~57.0.24",
    "expo-speech": "~57.0.3",
    "react": "19.2.3",
    "react-dom": "19.2.3",
    "react-native": "0.86.3",
    "react-native-safe-area-context": "~5.7.0",
    "react-native-web": "~0.21.0"
  },
  "devDependencies": {
    "@types/node": "~24.0.0",
    "@types/react": "~19.2.2",
    "typescript": "~6.0.3"
  }
}
```

### app.json

Конфигурация самостоятельного Expo-приложения.

```json
{
  "expo": {
    "name": "Text to Speech",
    "slug": "assignment-14-text-to-speech",
    "version": "1.0.0",
    "orientation": "default",
    "userInterfaceStyle": "light",
    "platforms": ["ios", "android", "web"],
    "ios": {
      "supportsTablet": true
    },
    "web": {
      "bundler": "metro",
      "output": "single"
    }
  }
}
```

### tsconfig.json

Строгая проверка типов исходников и тестов.

```json
{
  "extends": "expo/tsconfig.base",
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "allowImportingTsExtensions": true,
    "noEmit": true,
    "types": ["node", "react"]
  },
  "include": ["**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules", "dist", "dist-android", "dist-ios"]
}
```

### index.ts

Регистрация главного компонента, указанного через main в package.json.

```typescript
import { registerRootComponent } from 'expo';
import App from './App';

registerRootComponent(App);
```

### src/speech.ts

Языки, проверка ввода и последовательное управление речью.

```typescript
/** Pure TypeScript: this module has no React Native or Expo imports. */
export const LANGUAGES = [
  { label: 'English', code: 'en-US', example: 'Hello! How are you today?' },
  { label: 'Finnish', code: 'fi-FI', example: 'Hei! Mitä sinulle kuuluu?' },
  { label: 'Swedish', code: 'sv-SE', example: 'Hej! Hur mår du idag?' },
] as const;

export type Language = (typeof LANGUAGES)[number];
export type LanguageCode = Language['code'];

// A modest app limit also avoids submitting very long utterances on Android.
export const MAX_TEXT_LENGTH = 4000;

export function languageFromIndex(index: number): Language | undefined {
  return Number.isInteger(index) && index >= 0 ? LANGUAGES[index] : undefined;
}

export function speechInputLimit(engineMaximum?: number): number {
  if (engineMaximum === undefined || !Number.isFinite(engineMaximum) || engineMaximum < 1) {
    return MAX_TEXT_LENGTH;
  }
  return Math.min(MAX_TEXT_LENGTH, Math.floor(engineMaximum));
}

type ValidationReason = 'empty' | 'too-long' | 'invalid-language';
type FailureReason = ValidationReason | 'cancelled' | 'disposed' | 'engine';

export type SpeakResult =
  | { readonly ok: true }
  | { readonly ok: false; readonly reason: FailureReason; readonly message: string };

export type ValidatedRequest =
  | { readonly ok: true; readonly text: string; readonly language: Language }
  | { readonly ok: false; readonly reason: ValidationReason; readonly message: string };

export function validateSpeechRequest(
  text: string,
  selectedIndex: number,
  maximum = MAX_TEXT_LENGTH,
): ValidatedRequest {
  const trimmedText = text.trim();
  if (trimmedText.length === 0) {
    return { ok: false, reason: 'empty', message: 'Please enter some text before tapping SAY IT.' };
  }
  const language = languageFromIndex(selectedIndex);
  if (language === undefined) {
    return { ok: false, reason: 'invalid-language', message: 'Please select English, Finnish or Swedish.' };
  }
  const limit = speechInputLimit(maximum);
  if (trimmedText.length > limit) {
    return { ok: false, reason: 'too-long', message: `Please use at most ${limit} characters.` };
  }
  return { ok: true, text: trimmedText, language };
}

export interface SpeechOptions {
  readonly language: LanguageCode;
  readonly onStart: () => void;
  readonly onDone: () => void;
  readonly onStopped: () => void;
  readonly onError: (error: unknown) => void;
}

/** Injecting an adapter makes the controller testable without a device. */
export interface SpeechAdapter {
  readonly maxTextLength?: number;
  speak(text: string, options: SpeechOptions): void | Promise<void>;
  stop(): Promise<void>;
}

export type SpeechStatus = 'idle' | 'starting' | 'speaking' | 'stopping' | 'error';

export interface SpeechState {
  readonly status: SpeechStatus;
  readonly message: string;
  readonly language: LanguageCode | null;
}

export const INITIAL_SPEECH_STATE: SpeechState = {
  status: 'idle',
  message: 'Ready when you are.',
  language: null,
};

const cancelledResult: SpeakResult = {
  ok: false,
  reason: 'cancelled',
  message: 'Replaced by a newer action.',
};

// The native engine is shared. A remounted screen must wait for old cleanup too.
interface CommandQueue { tail: Promise<void> }
const adapterQueues = new WeakMap<SpeechAdapter, CommandQueue>();

function queueForAdapter(adapter: SpeechAdapter): CommandQueue {
  const existing = adapterQueues.get(adapter);
  if (existing !== undefined) return existing;
  const queue: CommandQueue = { tail: Promise.resolve() };
  adapterQueues.set(adapter, queue);
  return queue;
}

export class SpeechController {
  private readonly adapter: SpeechAdapter;
  readonly maxTextLength: number;
  private state: SpeechState = INITIAL_SPEECH_STATE;
  private readonly listeners = new Set<(state: SpeechState) => void>();
  private generation = 0;
  private disposed = false;
  private readonly commandQueue: CommandQueue;
  private cleanupPromise: Promise<void> | null = null;

  constructor(adapter: SpeechAdapter) {
    this.adapter = adapter;
    this.commandQueue = queueForAdapter(adapter);
    this.maxTextLength = speechInputLimit(adapter.maxTextLength);
  }

  getState(): SpeechState {
    return this.state;
  }

  subscribe(listener: (state: SpeechState) => void): () => void {
    if (this.disposed) return () => undefined;
    this.listeners.add(listener);
    listener(this.state);
    return () => {
      this.listeners.delete(listener);
    };
  }

  async say(text: string, selectedIndex: number): Promise<SpeakResult> {
    if (this.disposed) {
      return { ok: false, reason: 'disposed', message: 'The speech controller has been closed.' };
    }
    const request = validateSpeechRequest(text, selectedIndex, this.maxTextLength);
    // A validation failure does not interrupt a currently playing utterance.
    if (!request.ok) return request;

    const token = ++this.generation;
    this.update({ status: 'starting', message: `Preparing ${request.language.label} speech…`, language: request.language.code });

    return this.enqueue(async () => {
      if (!this.isCurrent(token)) return cancelledResult;

      try {
        // Speech.speak() queues utterances. Stopping first gives "replace" behavior.
        await this.adapter.stop();
      } catch {
        if (!this.isCurrent(token)) return cancelledResult;
        const message = 'Unable to stop the previous speech. Tap STOP and try again.';
        this.update({ status: 'error', message, language: request.language.code });
        return { ok: false, reason: 'engine', message };
      }

      if (!this.isCurrent(token)) return cancelledResult;
      let finished = false;
      const active = () => this.isCurrent(token) && !finished;
      const finish = (status: 'idle' | 'error', message: string) => {
        if (!active()) return;
        finished = true;
        this.update({ status, message, language: request.language.code });
      };

      try {
        await this.adapter.speak(request.text, {
          language: request.language.code,
          onStart: () => {
            if (active()) {
              this.update({ status: 'speaking', message: `Reading in ${request.language.label}…`, language: request.language.code });
            }
          },
          onDone: () => finish('idle', 'Finished reading.'),
          onStopped: () => finish('idle', 'Speech stopped.'),
          onError: () => finish('error', 'Unable to read this text. Check the selected voice on your device and try again.'),
        });
      } catch {
        if (!this.isCurrent(token)) return cancelledResult;
        finish('error', 'Unable to start speech. Please try again.');
        return { ok: false, reason: 'engine', message: this.state.message };
      }

      if (!this.isCurrent(token)) return cancelledResult;
      // Some engines do not report onStart. Do not overwrite a synchronous finish/error.
      if (!finished) {
        this.update({ status: 'speaking', message: `Reading in ${request.language.label}…`, language: request.language.code });
      }
      if (this.state.status === 'error') {
        return { ok: false, reason: 'engine', message: this.state.message };
      }
      return { ok: true };
    });
  }

  async stop(): Promise<boolean> {
    if (this.disposed) return false;
    const token = ++this.generation;
    this.update({ status: 'stopping', message: 'Stopping speech…', language: this.state.language });

    return this.enqueue(async () => {
      if (!this.isCurrent(token)) return false;
      try {
        await this.adapter.stop();
        if (!this.isCurrent(token)) return false;
        this.update({ status: 'idle', message: 'Speech stopped.', language: null });
        return true;
      } catch {
        if (this.isCurrent(token)) {
          this.update({ status: 'error', message: 'Unable to stop speech. Please try STOP again.', language: this.state.language });
        }
        return false;
      }
    });
  }

  dispose(): Promise<void> {
    if (this.cleanupPromise !== null) return this.cleanupPromise;
    this.disposed = true;
    ++this.generation;
    this.listeners.clear();
    this.cleanupPromise = this.enqueue(async () => {
      try {
        await this.adapter.stop();
      } catch {
        // There is no mounted screen to update; cleanup must not reject.
      }
    });
    return this.cleanupPromise;
  }

  private isCurrent(token: number): boolean {
    return !this.disposed && token === this.generation;
  }

  private update(state: SpeechState): void {
    if (this.disposed) return;
    this.state = state;
    for (const listener of this.listeners) listener(state);
  }

  private enqueue<T>(command: () => Promise<T>): Promise<T> {
    // Serial execution prevents a late stop from cancelling a newer utterance.
    const result = this.commandQueue.tail.then(command);
    this.commandQueue.tail = result.then(() => undefined, () => undefined);
    return result;
  }
}
```

### src/expoSpeech.ts

Адаптер системного синтезатора Expo Speech.

```typescript
import * as Speech from 'expo-speech';
import type { SpeechAdapter } from './speech';

/** The only file that connects the pure controller to Expo's speech engine. */
export const expoSpeechAdapter: SpeechAdapter = {
  maxTextLength: Speech.maxSpeechInputLength,
  stop: () => Speech.stop(),
  speak: (text, options) => {
    Speech.speak(text, {
      language: options.language,
      pitch: 1,
      rate: 1,
      onStart: options.onStart,
      onDone: options.onDone,
      onStopped: options.onStopped,
      onError: (error) => options.onError(error),
    });
  },
};
```

### src/LanguageSelector.tsx

Требуемый SegmentedControl для English, Finnish и Swedish.

```tsx
import SegmentedControl from '@react-native-segmented-control/segmented-control';
import { StyleSheet, Text, View } from 'react-native';
import { LANGUAGES, languageFromIndex } from './speech';

interface LanguageSelectorProps {
  selectedIndex: number;
  onSelect: (index: number) => void;
}

export function LanguageSelector({ selectedIndex, onSelect }: LanguageSelectorProps) {
  const selectedLanguage = languageFromIndex(selectedIndex);
  return (
    <View style={styles.container}>
      <Text style={styles.label}>Speech language</Text>
      <SegmentedControl
        values={LANGUAGES.map((language) => language.label)}
        selectedIndex={selectedIndex}
        onChange={(event) => {
          const nextIndex = event.nativeEvent.selectedSegmentIndex;
          if (languageFromIndex(nextIndex) !== undefined) onSelect(nextIndex);
        }}
        appearance="light"
        tintColor="#4358d0"
        backgroundColor="#e9edf8"
        fontStyle={{ fontSize: 14, fontWeight: '500', color: '#34405c' }}
        activeFontStyle={{ fontSize: 14, fontWeight: '600', color: '#ffffff' }}
        style={styles.control}
        accessibilityLabel="Select the speech language: English, Finnish or Swedish"
        accessibilityHint="Changes the voice language for the next time you tap SAY IT"
      />
      <Text style={styles.hint}>Example: {selectedLanguage?.example ?? ''}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { gap: 12 },
  label: { color: '#253250', fontSize: 16, fontWeight: '600' },
  control: { height: 44, width: '100%' },
  hint: { color: '#66728c', fontSize: 13, lineHeight: 20 },
});
```

### App.tsx

Поле ввода, выбор языка, SAY IT/STOP, состояние и очистка после ухода с экрана.

```tsx
import { useEffect, useRef, useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { LanguageSelector } from './src/LanguageSelector';
import { expoSpeechAdapter } from './src/expoSpeech';
import {
  INITIAL_SPEECH_STATE,
  SpeechController,
  speechInputLimit,
  type SpeechState,
} from './src/speech';

function SpeechScreen() {
  const [text, setText] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [inputError, setInputError] = useState<string | null>(null);
  const [speechState, setSpeechState] = useState<SpeechState>(INITIAL_SPEECH_STATE);
  const controllerRef = useRef<SpeechController | null>(null);
  const latestAction = useRef(0);
  const inputLimit = speechInputLimit(expoSpeechAdapter.maxTextLength);

  useEffect(() => {
    // Create a fresh controller for each mounted subscription, including Strict Mode.
    const controller = new SpeechController(expoSpeechAdapter);
    controllerRef.current = controller;
    const unsubscribe = controller.subscribe(setSpeechState);
    return () => {
      ++latestAction.current;
      controllerRef.current = null;
      unsubscribe();
      void controller.dispose();
    };
  }, []);

  const handleSay = async () => {
    const controller = controllerRef.current;
    if (controller === null) return;
    const action = ++latestAction.current;
    setInputError(null);
    const result = await controller.say(text, selectedIndex);
    if (controllerRef.current !== controller || action !== latestAction.current) return;
    if (!result.ok && ['empty', 'too-long', 'invalid-language'].includes(result.reason)) {
      setInputError(result.message);
    }
  };

  const handleStop = () => {
    ++latestAction.current;
    setInputError(null);
    void controllerRef.current?.stop();
  };

  const changeText = (value: string) => {
    ++latestAction.current;
    setText(value);
    setInputError(null);
  };

  const changeLanguage = (index: number) => {
    ++latestAction.current;
    setSelectedIndex(index);
    setInputError(null);
  };

  const stopDisabled = speechState.status === 'idle';
  const hasSpeechError = speechState.status === 'error';

  return (
    <SafeAreaView style={styles.screen}>
      <StatusBar barStyle="dark-content" />
      <KeyboardAvoidingView
        style={styles.screen}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
        >
          <View style={styles.content}>
            <View style={styles.heading}>
              <Text style={styles.eyebrow}>ASSIGNMENT 14 · TEXT TO SPEECH</Text>
              <Text style={styles.title} accessibilityRole="header">Give your words{ '\n' }a voice.</Text>
              <Text style={styles.subtitle}>Choose a language, type a sentence, then tap SAY IT.</Text>
            </View>

            <View style={styles.card}>
              <LanguageSelector selectedIndex={selectedIndex} onSelect={changeLanguage} />
              <View style={styles.fieldSection}>
                <View style={styles.fieldHeading}>
                  <Text style={styles.label}>Your text</Text>
                  <Text style={styles.counter} accessibilityLabel={`${text.length} of ${inputLimit} characters used`}>
                    {text.length} / {inputLimit}
                  </Text>
                </View>
                <TextInput
                  value={text}
                  onChangeText={changeText}
                  multiline
                  maxLength={inputLimit}
                  placeholder="Write something to say…"
                  placeholderTextColor="#858fa5"
                  textAlignVertical="top"
                  style={[styles.textInput, inputError !== null && styles.invalidInput]}
                  accessibilityLabel="Text to read aloud"
                  accessibilityHint="Enter the text, then tap SAY IT to hear it in the selected language"
                  autoCorrect
                  spellCheck
                />
                {inputError !== null && (
                  <Text style={styles.inputError} accessibilityRole="alert" accessibilityLiveRegion="assertive">
                    {inputError}
                  </Text>
                )}
              </View>

              <View style={styles.actions}>
                <Pressable
                  onPress={() => void handleSay()}
                  style={({ pressed }) => [styles.button, styles.sayButton, pressed && styles.pressed]}
                  accessibilityRole="button"
                  accessibilityLabel="SAY IT"
                  accessibilityHint="Stops any previous speech and reads the entered text"
                >
                  <Text style={styles.sayButtonText}>SAY IT</Text>
                </Pressable>
                <Pressable
                  onPress={handleStop}
                  disabled={stopDisabled}
                  style={({ pressed }) => [styles.button, styles.stopButton, stopDisabled && styles.disabled, pressed && styles.pressed]}
                  accessibilityRole="button"
                  accessibilityLabel="STOP"
                  accessibilityHint="Stops reading and clears pending speech"
                  accessibilityState={{ disabled: stopDisabled }}
                >
                  <Text style={styles.stopButtonText}>STOP</Text>
                </Pressable>
              </View>

              <View style={[styles.status, hasSpeechError && styles.errorStatus]}>
                <View style={[styles.statusDot, hasSpeechError && styles.errorDot]} />
                <Text
                  style={[styles.statusText, hasSpeechError && styles.errorStatusText]}
                  accessibilityLiveRegion="polite"
                  accessibilityRole={hasSpeechError ? 'alert' : 'text'}
                >
                  {speechState.message}
                </Text>
              </View>
            </View>

            <View style={styles.help}>
              <Text style={styles.helpTitle}>A small listening tip</Text>
              <Text style={styles.helpText}>The selected language changes pronunciation. It does not translate your text.</Text>
              <Text style={styles.helpText}>Voices depend on your device. If there is no sound, check volume and silent mode.</Text>
            </View>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <SpeechScreen />
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#f3f5fb' },
  scrollContent: { flexGrow: 1, alignItems: 'center', paddingHorizontal: 20, paddingVertical: 30 },
  content: { width: '100%', maxWidth: 640, gap: 24 },
  heading: { gap: 12, paddingHorizontal: 4 },
  eyebrow: { fontSize: 11, fontWeight: '700', letterSpacing: 1.3, color: '#5265c3', lineHeight: 18 },
  title: { color: '#202b48', fontSize: 34, fontWeight: '700', letterSpacing: -0.7, lineHeight: 42 },
  subtitle: { color: '#66728c', fontSize: 16, lineHeight: 25, maxWidth: 430 },
  card: { backgroundColor: '#ffffff', padding: 20, borderRadius: 22, borderColor: '#e1e6f2', borderWidth: 1, gap: 24 },
  fieldSection: { gap: 10 },
  fieldHeading: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  label: { color: '#253250', fontSize: 16, fontWeight: '600' },
  counter: { color: '#7a859c', fontSize: 12 },
  textInput: { minHeight: 168, maxHeight: 280, padding: 16, backgroundColor: '#f8f9fc', borderRadius: 14, borderWidth: 1, borderColor: '#d8dfed', color: '#253250', fontSize: 17, lineHeight: 26 },
  invalidInput: { borderColor: '#c55757' },
  inputError: { color: '#aa3434', fontSize: 14, lineHeight: 21 },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  button: { flex: 1, minWidth: 100, minHeight: 52, alignItems: 'center', justifyContent: 'center', borderRadius: 13, paddingHorizontal: 18, paddingVertical: 15 },
  sayButton: { backgroundColor: '#4358d0' },
  stopButton: { backgroundColor: '#eef1f9', borderWidth: 1, borderColor: '#dbe1ef' },
  sayButtonText: { color: '#ffffff', fontSize: 15, letterSpacing: 1, fontWeight: '700' },
  stopButtonText: { color: '#435079', fontSize: 15, letterSpacing: 1, fontWeight: '700' },
  disabled: { opacity: 0.45 },
  pressed: { opacity: 0.75 },
  status: { borderRadius: 12, backgroundColor: '#eef8f6', padding: 12, flexDirection: 'row', alignItems: 'center', gap: 9 },
  statusDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: '#3a867a' },
  statusText: { color: '#376c64', fontSize: 13, lineHeight: 20, flex: 1 },
  errorStatus: { backgroundColor: '#fff0f0' },
  errorDot: { backgroundColor: '#b44c4c' },
  errorStatusText: { color: '#a34040' },
  help: { paddingHorizontal: 6, gap: 8, paddingBottom: 12 },
  helpTitle: { color: '#475572', fontWeight: '600', fontSize: 14 },
  helpText: { color: '#738099', fontSize: 13, lineHeight: 21 },
});
```

### tests/speech.test.ts

Тесты языков, валидации, порядка команд и запоздавших событий.

```typescript
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  LANGUAGES,
  MAX_TEXT_LENGTH,
  SpeechController,
  languageFromIndex,
  speechInputLimit,
  validateSpeechRequest,
  type SpeechAdapter,
  type SpeechOptions,
  type SpeechState,
} from '../src/speech.ts';

interface Utterance {
  text: string;
  options: SpeechOptions;
}

class FakeSpeech implements SpeechAdapter {
  readonly calls: string[] = [];
  readonly utterances: Utterance[] = [];
  readonly maxTextLength: number;
  stopError: Error | null = null;
  speakError: Error | null = null;
  stopImplementation: (() => Promise<void>) | null = null;
  speakImplementation: ((options: SpeechOptions) => void | Promise<void>) | null = null;

  constructor(maximum = MAX_TEXT_LENGTH) {
    this.maxTextLength = maximum;
  }

  async stop(): Promise<void> {
    this.calls.push('stop');
    if (this.stopError !== null) throw this.stopError;
    if (this.stopImplementation !== null) await this.stopImplementation();
  }

  speak(text: string, options: SpeechOptions): void | Promise<void> {
    this.calls.push('speak');
    if (this.speakError !== null) throw this.speakError;
    this.utterances.push({ text, options });
    return this.speakImplementation?.(options);
  }
}

function latestUtterance(engine: FakeSpeech): Utterance {
  const utterance = engine.utterances.at(-1);
  assert.ok(utterance);
  return utterance;
}

function deferred() {
  let resolve: () => void = () => undefined;
  const promise = new Promise<void>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

test('the three segment indices map to the required language codes', async () => {
  assert.deepEqual(LANGUAGES.map((language) => language.code), ['en-US', 'fi-FI', 'sv-SE']);
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  for (let index = 0; index < LANGUAGES.length; ++index) {
    assert.equal((await controller.say('Hello', index)).ok, true);
    assert.equal(latestUtterance(engine).options.language, LANGUAGES[index]?.code);
  }
  assert.equal(languageFromIndex(-1), undefined);
  assert.equal(languageFromIndex(3), undefined);
  assert.equal(languageFromIndex(0.5), undefined);
  assert.equal(languageFromIndex(Number.NaN), undefined);
});

test('blank text, invalid indices and overlong input never call the engine', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  for (const text of ['', '   ', '\n\t\r ']) {
    assert.deepEqual(await controller.say(text, 0), {
      ok: false,
      reason: 'empty',
      message: 'Please enter some text before tapping SAY IT.',
    });
  }
  for (const index of [-1, 3, 1.5, Number.NaN, Number.POSITIVE_INFINITY]) {
    const result = await controller.say('Hello', index);
    assert.equal(result.ok, false);
    if (!result.ok) assert.equal(result.reason, 'invalid-language');
  }
  const result = await controller.say('x'.repeat(MAX_TEXT_LENGTH + 1), 0);
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.reason, 'too-long');
  assert.deepEqual(engine.calls, []);
});

test('validation trims outer whitespace and observes the smaller engine limit', async () => {
  assert.deepEqual(validateSpeechRequest('  Hello\n ', 0), { ok: true, text: 'Hello', language: LANGUAGES[0] });
  assert.equal(speechInputLimit(3), 3);
  assert.equal(speechInputLimit(5000), MAX_TEXT_LENGTH);
  assert.equal(speechInputLimit(Number.POSITIVE_INFINITY), MAX_TEXT_LENGTH);
  assert.equal(speechInputLimit(0), MAX_TEXT_LENGTH);
  const engine = new FakeSpeech(3);
  const controller = new SpeechController(engine);
  assert.equal((await controller.say('Hello', 0)).ok, false);
  assert.deepEqual(engine.calls, []);
  assert.equal((await controller.say('  Hi  ', 0)).ok, true);
  assert.equal(latestUtterance(engine).text, 'Hi');
});

test('each successful request stops previous speech before speaking', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  assert.equal((await controller.say('First', 0)).ok, true);
  assert.equal((await controller.say('Second', 1)).ok, true);
  assert.deepEqual(engine.calls, ['stop', 'speak', 'stop', 'speak']);
  assert.equal(controller.getState().status, 'speaking');
  latestUtterance(engine).options.onDone();
  assert.equal(controller.getState().status, 'idle');
  assert.equal(controller.getState().message, 'Finished reading.');
});

test('a failed stop prevents speaking and the next request can recover', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  engine.stopError = new Error('stop failed');
  const result = await controller.say('Hello', 0);
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.reason, 'engine');
  assert.deepEqual(engine.calls, ['stop']);
  assert.equal(controller.getState().status, 'error');
  engine.stopError = null;
  assert.equal((await controller.say('Try again', 0)).ok, true);
  assert.deepEqual(engine.calls, ['stop', 'stop', 'speak']);
});

test('a synchronous speak exception and an asynchronous rejection are handled', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  engine.speakError = new Error('speak failed');
  assert.equal((await controller.say('Hello', 0)).ok, false);
  assert.equal(controller.getState().status, 'error');
  engine.speakError = null;
  engine.speakImplementation = () => Promise.reject(new Error('async failure'));
  assert.equal((await controller.say('Hello', 0)).ok, false);
  assert.equal(controller.getState().status, 'error');
  engine.speakImplementation = null;
  assert.equal((await controller.say('Recovered', 0)).ok, true);
});

test('late callbacks from a replaced utterance cannot change current state', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  await controller.say('First', 0);
  const oldOptions = latestUtterance(engine).options;
  await controller.say('Second', 2);
  const currentState = controller.getState();
  oldOptions.onStart();
  oldOptions.onDone();
  oldOptions.onStopped();
  oldOptions.onError(new Error('late error'));
  assert.deepEqual(controller.getState(), currentState);
  latestUtterance(engine).options.onError(new Error('current error'));
  assert.equal(controller.getState().status, 'error');
});

test('a terminal callback cannot be undone by a later onStart or onDone', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  await controller.say('Hello', 0);
  const options = latestUtterance(engine).options;
  options.onStopped();
  const finished = controller.getState();
  options.onStart();
  options.onDone();
  options.onError(new Error('late failure'));
  assert.deepEqual(controller.getState(), finished);
});

test('synchronous completion or error during speak is not overwritten', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  engine.speakImplementation = (options) => options.onDone();
  assert.equal((await controller.say('Done', 0)).ok, true);
  assert.equal(controller.getState().status, 'idle');
  engine.speakImplementation = (options) => options.onError(new Error('no voice'));
  assert.equal((await controller.say('Error', 0)).ok, false);
  assert.equal(controller.getState().status, 'error');
});

test('rapid requests made before processing only speak the newest text', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  const first = controller.say('First', 0);
  const second = controller.say('Second', 1);
  const third = controller.say('Third', 2);
  const results = await Promise.all([first, second, third]);
  assert.equal(results[0]?.ok, false);
  assert.equal(results[1]?.ok, false);
  assert.equal(results[2]?.ok, true);
  assert.deepEqual(engine.calls, ['stop', 'speak']);
  assert.equal(latestUtterance(engine).text, 'Third');
  assert.equal(latestUtterance(engine).options.language, 'sv-SE');
});

test('an in-flight stop finishes before the newest request is allowed to speak', async () => {
  const engine = new FakeSpeech();
  const blockedStop = deferred();
  let stopCount = 0;
  engine.stopImplementation = () => ++stopCount === 1 ? blockedStop.promise : Promise.resolve();
  const controller = new SpeechController(engine);
  const first = controller.say('First', 0);
  await Promise.resolve();
  assert.deepEqual(engine.calls, ['stop']);
  const second = controller.say('Second', 1);
  blockedStop.resolve();
  assert.equal((await first).ok, false);
  assert.equal((await second).ok, true);
  assert.deepEqual(engine.calls, ['stop', 'stop', 'speak']);
  assert.equal(latestUtterance(engine).text, 'Second');
});

test('STOP cancels a pending start and ignores callbacks of previous speech', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  await controller.say('Playing', 0);
  const oldOptions = latestUtterance(engine).options;
  const pending = controller.say('Pending', 1);
  const stopped = controller.stop();
  assert.equal((await pending).ok, false);
  assert.equal(await stopped, true);
  const state = controller.getState();
  oldOptions.onStart();
  oldOptions.onDone();
  oldOptions.onStopped();
  oldOptions.onError(new Error('late error'));
  assert.deepEqual(controller.getState(), state);
  assert.equal(state.status, 'idle');
  assert.equal(engine.utterances.length, 1);
});

test('a failed explicit STOP reports an error and allows a retry', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  await controller.say('Hello', 0);
  engine.stopError = new Error('stop failed');
  assert.equal(await controller.stop(), false);
  assert.equal(controller.getState().status, 'error');
  engine.stopError = null;
  assert.equal(await controller.stop(), true);
  assert.equal(controller.getState().status, 'idle');
});

test('invalid input does not interrupt existing speech', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  await controller.say('Playing', 0);
  const state = controller.getState();
  const result = await controller.say('   ', 0);
  assert.equal(result.ok, false);
  assert.deepEqual(engine.calls, ['stop', 'speak']);
  assert.deepEqual(controller.getState(), state);
});

test('disposal stops playback, removes listeners and rejects future actions', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  const snapshots: SpeechState[] = [];
  controller.subscribe((state) => snapshots.push(state));
  await controller.say('Hello', 0);
  const options = latestUtterance(engine).options;
  const beforeDisposal = snapshots.length;
  const cleanup = controller.dispose();
  assert.equal(controller.dispose(), cleanup);
  await cleanup;
  options.onDone();
  options.onError(new Error('late error'));
  assert.equal(snapshots.length, beforeDisposal);
  const result = await controller.say('After unmount', 0);
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.reason, 'disposed');
  assert.equal(await controller.stop(), false);
  assert.deepEqual(engine.calls, ['stop', 'speak', 'stop']);
});

test('disposal during a pending stop never starts speech', async () => {
  const engine = new FakeSpeech();
  const blockedStop = deferred();
  let count = 0;
  engine.stopImplementation = () => ++count === 1 ? blockedStop.promise : Promise.resolve();
  const controller = new SpeechController(engine);
  const start = controller.say('Never read this', 0);
  await Promise.resolve();
  const cleanup = controller.dispose();
  blockedStop.resolve();
  assert.equal((await start).ok, false);
  await cleanup;
  assert.equal(engine.utterances.length, 0);
  assert.deepEqual(engine.calls, ['stop', 'stop']);
});

test('cleanup tolerates engine failure and unsubscribed listeners remain silent', async () => {
  const engine = new FakeSpeech();
  const controller = new SpeechController(engine);
  let updates = 0;
  const unsubscribe = controller.subscribe(() => ++updates);
  assert.equal(updates, 1);
  unsubscribe();
  await controller.say('Hello', 0);
  assert.equal(updates, 1);
  engine.stopError = new Error('cleanup failed');
  await assert.doesNotReject(controller.dispose());
  controller.subscribe(() => ++updates);
  assert.equal(updates, 1);
});

test('old screen cleanup finishes before a remounted screen starts new speech', async () => {
  const engine = new FakeSpeech();
  const blockedStop = deferred();
  let count = 0;
  let playing: string | null = null;
  engine.stopImplementation = async () => {
    if (++count === 1) await blockedStop.promise;
    playing = null;
  };
  engine.speakImplementation = () => {
    playing = latestUtterance(engine).text;
  };
  const oldController = new SpeechController(engine);
  const pending = oldController.say('Old screen', 0);
  await Promise.resolve();
  const cleanup = oldController.dispose();
  const newController = new SpeechController(engine);
  const newSpeech = newController.say('New screen', 1);
  await Promise.resolve();
  await Promise.resolve();
  blockedStop.resolve();
  await Promise.all([pending, cleanup, newSpeech]);
  assert.equal(playing, 'New screen');
  assert.deepEqual(engine.calls, ['stop', 'stop', 'stop', 'speak']);
  assert.equal(newController.getState().status, 'speaking');
});
```

### .gitignore

Исключения для зависимостей, сборок и локальных файлов.

```text
node_modules/
.expo/
dist/
dist-android/
dist-ios/
*.log
.DS_Store
```
