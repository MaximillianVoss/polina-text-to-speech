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
