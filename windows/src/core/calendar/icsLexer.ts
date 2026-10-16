/*
 * The content-line layer of RFC 5545 (iCalendar): unfolding, one property
 * per line with its parameters, BEGIN/END nesting, and TEXT unescaping. It
 * reads anything without throwing: a line it cannot make sense of is
 * skipped, and components left open at the end of the text are closed.
 */

/** One content line: `NAME;PARAM=a,b:value`. Names and parameter names are upper case. */
export interface IcsProperty {
  readonly name: string;
  readonly params: Readonly<Record<string, readonly string[]>>;
  readonly value: string;
}

/** A BEGIN/END block such as VCALENDAR, VEVENT or VTIMEZONE, with what it holds. */
export interface IcsComponent {
  readonly name: string;
  readonly properties: IcsProperty[];
  readonly components: IcsComponent[];
}

/** Joins folded lines: a line break followed by one space or tab continues the line before it. */
export function unfoldLines(text: string): string[] {
  const body = text.startsWith("﻿") ? text.slice(1) : text;
  return body
    .replace(/\r\n[ \t]|\n[ \t]|\r[ \t]/g, "")
    .split(/\r\n|\n|\r/)
    .filter((line) => line.trim() !== "");
}

/** Parses one content line, or undefined when it has no name or no colon. */
export function parseContentLine(line: string): IcsProperty | undefined {
  let index = 0;
  const length = line.length;
  while (index < length && line[index] !== ";" && line[index] !== ":") index++;
  const name = line.slice(0, index).trim().toUpperCase();
  if (name === "" || index >= length) return undefined;
  const params: Record<string, string[]> = {};
  while (index < length && line[index] === ";") {
    index++;
    let nameEnd = index;
    while (nameEnd < length && line[nameEnd] !== "=" && line[nameEnd] !== ";" && line[nameEnd] !== ":") nameEnd++;
    const paramName = line.slice(index, nameEnd).trim().toUpperCase();
    index = nameEnd;
    const values: string[] = [];
    if (line[index] === "=") {
      index++;
      for (;;) {
        let value: string;
        if (line[index] === '"') {
          const close = line.indexOf('"', index + 1);
          if (close < 0) {
            value = line.slice(index + 1);
            index = length;
          } else {
            value = line.slice(index + 1, close);
            index = close + 1;
          }
        } else {
          let end = index;
          while (end < length && line[end] !== "," && line[end] !== ";" && line[end] !== ":") end++;
          value = line.slice(index, end);
          index = end;
        }
        values.push(value);
        if (line[index] === ",") {
          index++;
          continue;
        }
        break;
      }
    }
    if (paramName !== "") params[paramName] = [...(params[paramName] ?? []), ...values];
  }
  if (line[index] !== ":") return undefined;
  return { name, params, value: line.slice(index + 1) };
}

/**
 * The components in `text`, as children of a synthetic root named "" (a
 * feed normally holds one VCALENDAR). Properties outside any component are
 * kept on the root.
 */
export function parseComponents(text: string): IcsComponent {
  const root: IcsComponent = { name: "", properties: [], components: [] };
  const stack: IcsComponent[] = [root];
  for (const line of unfoldLines(text)) {
    const property = parseContentLine(line);
    if (property === undefined) continue;
    const current = stack[stack.length - 1] ?? root;
    if (property.name === "BEGIN") {
      const component: IcsComponent = { name: property.value.trim().toUpperCase(), properties: [], components: [] };
      current.components.push(component);
      stack.push(component);
    } else if (property.name === "END") {
      const name = property.value.trim().toUpperCase();
      const open = stack.findLastIndex((component, position) => position > 0 && component.name === name);
      if (open > 0) stack.length = open;
    } else {
      current.properties.push(property);
    }
  }
  return root;
}

/** The first property named `name`, if any. */
export function property(component: IcsComponent, name: string): IcsProperty | undefined {
  return component.properties.find((entry) => entry.name === name);
}

/** Every property named `name`, in order. */
export function properties(component: IcsComponent, name: string): IcsProperty[] {
  return component.properties.filter((entry) => entry.name === name);
}

/** The first value of a parameter, if any. */
export function param(entry: IcsProperty, name: string): string | undefined {
  return entry.params[name]?.[0];
}

/** A TEXT value with its escapes (`\n`, `\,`, `\;`, `\\`) undone. */
export function unescapeText(value: string): string {
  return value.replace(/\\([nN,;\\:])/g, (_match, escaped: string) => (escaped === "n" || escaped === "N" ? "\n" : escaped));
}
