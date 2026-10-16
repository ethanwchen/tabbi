import { describe, expect, it } from "vitest";
import { constant, derived, Emitter, mapped, Observable, Store } from "../../../src/app/store";

class Counter extends Store<{ count: number; label: string }> {
  constructor() {
    super({ count: 0, label: "a" });
  }

  increment() {
    this.setState((state) => ({ count: state.count + 1 }));
  }

  label(text: string) {
    this.setState({ label: text });
  }
}

describe("Observable", () => {
  it("notifies only when the value changes", () => {
    const value = new Observable(1);
    let heard = 0;
    const stop = value.subscribe(() => heard++);
    value.set(1);
    value.set(2);
    value.update((v) => v + 1);
    expect(value.get()).toBe(3);
    expect(heard).toBe(2);
    stop();
    value.set(4);
    expect(heard).toBe(2);
    expect(value.subscriberCount).toBe(0);
  });

  it("compares with a given equality", () => {
    const value = new Observable<number[]>([1], (a, b) => a.join() === b.join());
    let heard = 0;
    value.subscribe(() => heard++);
    value.set([1]);
    expect(heard).toBe(0);
    value.set([1, 2]);
    expect(heard).toBe(1);
  });
});

describe("Store", () => {
  it("merges patches and keeps the same state object when nothing differs", () => {
    const store = new Counter();
    const first = store.get();
    let heard = 0;
    store.subscribe(() => heard++);
    store.label("a");
    expect(store.get()).toBe(first);
    store.increment();
    store.label("b");
    expect(store.state).toEqual({ count: 1, label: "b" });
    expect(heard).toBe(2);
  });
});

describe("Emitter", () => {
  it("tells every listener until it stops", () => {
    const emitter = new Emitter<string>();
    const heard: string[] = [];
    const stop = emitter.on((event) => heard.push(event));
    emitter.emit("a");
    stop();
    emitter.emit("b");
    expect(heard).toEqual(["a"]);
  });
});

describe("derived and mapped", () => {
  it("recomputes from its sources and notifies only on real changes", () => {
    const a = new Observable(1);
    const b = new Observable(10);
    let computed = 0;
    const sum = derived([a, b], () => {
      computed++;
      return a.get() + b.get() > 15;
    });
    let heard = 0;
    const stop = sum.subscribe(() => heard++);
    expect(sum.get()).toBe(false);
    a.set(2);
    expect(heard).toBe(0);
    b.set(20);
    expect(sum.get()).toBe(true);
    expect(heard).toBe(1);
    stop();
    a.set(3);
    const before = computed;
    sum.get();
    expect(computed).toBe(before + 1);
  });

  it("maps a store once per state", () => {
    const store = new Counter();
    let calls = 0;
    const doubled = mapped(store, (state) => {
      calls++;
      return { value: state.count * 2 };
    });
    const first = doubled.get();
    expect(doubled.get()).toBe(first);
    store.increment();
    expect(doubled.get().value).toBe(2);
    expect(calls).toBe(2);
  });

  it("keeps a constant", () => {
    const value = constant(5);
    expect(value.get()).toBe(5);
    value.subscribe(() => undefined)();
  });
});
