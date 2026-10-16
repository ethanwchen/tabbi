/*
 * The Mac's `Logger(subsystem: "Tabbi", category: <module id>)`: messages go
 * to the webview's console under the module's id, for development only.
 * Logs never leave the PC (no telemetry), and never hold typed text, tokens
 * or names.
 */

export interface Logger {
  debug(message: string, ...details: unknown[]): void;
  info(message: string, ...details: unknown[]): void;
  warning(message: string, ...details: unknown[]): void;
  error(message: string, ...details: unknown[]): void;
}

/** Where log lines go; the console by default, a list in tests. */
export type LogSink = (level: "debug" | "info" | "warning" | "error", category: string, message: string, details: readonly unknown[]) => void;

export const consoleSink: LogSink = (level, category, message, details) => {
  const line = `[tabbi:${category}] ${message}`;
  if (level === "error") console.error(line, ...details);
  else if (level === "warning") console.warn(line, ...details);
  else if (level === "info") console.info(line, ...details);
  else console.debug(line, ...details);
};

/** A logger whose lines name `category` (a module id, or "app"). */
export function makeLogger(category: string, sink: LogSink = consoleSink): Logger {
  return {
    debug: (message, ...details) => sink("debug", category, message, details),
    info: (message, ...details) => sink("info", category, message, details),
    warning: (message, ...details) => sink("warning", category, message, details),
    error: (message, ...details) => sink("error", category, message, details),
  };
}

/** Drops every line, for snapshot runs and tests that do not care. */
export const silentSink: LogSink = () => {};
