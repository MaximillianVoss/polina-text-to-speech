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
