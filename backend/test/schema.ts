/**
 * A small JSON Schema (draft 2020-12) checker for the subset the shared schemas (party.v1 and crews.v1)
 * use: type, const, enum, pattern, minimum, maximum, minLength, maxLength, minItems, maxItems,
 * uniqueItems, required, properties, additionalProperties false, items, oneOf and local $ref. It keeps
 * the backend free of a validator dependency, and it fails on any keyword it does not know, so a schema
 * cannot grow past what this checks without notice.
 */
import schema from "../../shared/schemas/party.v1.schema.json";
import crews from "../../shared/schemas/crews.v1.schema.json";

type Node = Record<string, unknown>;
const KNOWN = new Set([
  "$schema", "$id", "title", "description", "$defs", "$ref", "type", "const", "enum", "pattern", "minimum", "maximum",
  "maxItems", "uniqueItems", "required", "properties", "additionalProperties", "items", "oneOf",
  "minLength", "maxLength", "minItems",
]);

export const partySchema = schema as unknown as Node;
export const crewsSchema = crews as unknown as Node;

/** The problems with `value` against the Party schema's `$defs[name]`; empty when it conforms. */
export function check(name: string, value: unknown): string[] {
  return checkAgainst(partySchema, name, value);
}

/** The problems with `value` against the Crews schema's `$defs[name]`; empty when it conforms. */
export function checkCrews(name: string, value: unknown): string[] {
  return checkAgainst(crewsSchema, name, value);
}

function checkAgainst(root: Node, name: string, value: unknown): string[] {
  const defs = root.$defs as Record<string, Node>;
  if (!defs[name]) throw new Error(`no $defs/${name} in ${String(root.title)}`);
  return validate(root, defs[name], value, name);
}

function typeOf(v: unknown): string {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  if (typeof v === "number") return Number.isInteger(v) ? "integer" : "number";
  return typeof v;
}

function validate(root: Node, node: Node, value: unknown, at: string): string[] {
  for (const key of Object.keys(node)) if (!KNOWN.has(key)) throw new Error(`${at}: unsupported keyword ${key}`);
  if (typeof node.$ref === "string") {
    const name = node.$ref.replace("#/$defs/", "");
    return validate(root, (root.$defs as Record<string, Node>)[name], value, at);
  }
  const problems: string[] = [];
  const type = typeOf(value);
  if (node.type !== undefined) {
    const allowed = Array.isArray(node.type) ? node.type as string[] : [node.type as string];
    const ok = allowed.includes(type) || (type === "integer" && allowed.includes("number"));
    if (!ok) return [`${at}: expected ${allowed.join(" or ")}, got ${type}`];
  }
  if ("const" in node && value !== node.const) problems.push(`${at}: expected ${JSON.stringify(node.const)}`);
  if (Array.isArray(node.enum) && !node.enum.includes(value)) problems.push(`${at}: ${JSON.stringify(value)} is not one of ${node.enum.join(", ")}`);
  if (typeof node.pattern === "string" && typeof value === "string" && !new RegExp(node.pattern).test(value)) {
    problems.push(`${at}: ${JSON.stringify(value)} does not match ${node.pattern}`);
  }
  if (typeof node.minimum === "number" && typeof value === "number" && value < node.minimum) problems.push(`${at}: below ${node.minimum}`);
  if (typeof node.maximum === "number" && typeof value === "number" && value > node.maximum) problems.push(`${at}: above ${node.maximum}`);
  if (typeof value === "string") {
    const length = [...value].length;
    if (typeof node.minLength === "number" && length < node.minLength) problems.push(`${at}: shorter than ${node.minLength}`);
    if (typeof node.maxLength === "number" && length > node.maxLength) problems.push(`${at}: longer than ${node.maxLength}`);
  }
  if (Array.isArray(node.oneOf)) {
    const matching = (node.oneOf as Node[]).filter((option) => validate(root, option, value, at).length === 0).length;
    if (matching !== 1) problems.push(`${at}: matches ${matching} of oneOf`);
  }
  if (type === "array") {
    const list = value as unknown[];
    if (typeof node.maxItems === "number" && list.length > node.maxItems) problems.push(`${at}: more than ${node.maxItems} items`);
    if (typeof node.minItems === "number" && list.length < node.minItems) problems.push(`${at}: fewer than ${node.minItems} items`);
    if (node.uniqueItems === true && new Set(list.map((v) => JSON.stringify(v))).size !== list.length) problems.push(`${at}: repeated items`);
    if (node.items) list.forEach((item, i) => problems.push(...validate(root, node.items as Node, item, `${at}[${i}]`)));
  }
  if (type === "object") {
    const object = value as Record<string, unknown>;
    for (const key of (node.required as string[] | undefined) ?? []) {
      if (!(key in object)) problems.push(`${at}: missing ${key}`);
    }
    const properties = (node.properties as Record<string, Node> | undefined) ?? {};
    for (const [key, child] of Object.entries(object)) {
      if (properties[key]) problems.push(...validate(root, properties[key], child, `${at}.${key}`));
      else if (node.additionalProperties === false) problems.push(`${at}: unexpected ${key}`);
    }
  }
  return problems;
}
