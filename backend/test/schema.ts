/**
 * A small JSON Schema (draft 2020-12) checker for the subset shared/schemas/party.v1.schema.json uses:
 * type, const, enum, pattern, minimum, maxItems, uniqueItems, required, properties, additionalProperties
 * false, items, oneOf and local $ref. It keeps the backend free of a validator dependency, and it fails
 * on any keyword it does not know, so the schema cannot grow past what this checks without notice.
 */
import schema from "../../shared/schemas/party.v1.schema.json";

type Node = Record<string, unknown>;
const KNOWN = new Set([
  "$schema", "$id", "title", "description", "$defs", "$ref", "type", "const", "enum", "pattern", "minimum",
  "maxItems", "uniqueItems", "required", "properties", "additionalProperties", "items", "oneOf",
]);

export const partySchema = schema as unknown as Node;

/** The problems with `value` against `$defs[name]`; empty when it conforms. */
export function check(name: string, value: unknown): string[] {
  const defs = partySchema.$defs as Record<string, Node>;
  if (!defs[name]) throw new Error(`no $defs/${name} in the Party schema`);
  return validate(defs[name], value, name);
}

function typeOf(v: unknown): string {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  if (typeof v === "number") return Number.isInteger(v) ? "integer" : "number";
  return typeof v;
}

function validate(node: Node, value: unknown, at: string): string[] {
  for (const key of Object.keys(node)) if (!KNOWN.has(key)) throw new Error(`${at}: unsupported keyword ${key}`);
  if (typeof node.$ref === "string") {
    const name = node.$ref.replace("#/$defs/", "");
    return validate((partySchema.$defs as Record<string, Node>)[name], value, at);
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
  if (Array.isArray(node.oneOf)) {
    const matching = (node.oneOf as Node[]).filter((option) => validate(option, value, at).length === 0).length;
    if (matching !== 1) problems.push(`${at}: matches ${matching} of oneOf`);
  }
  if (type === "array") {
    const list = value as unknown[];
    if (typeof node.maxItems === "number" && list.length > node.maxItems) problems.push(`${at}: more than ${node.maxItems} items`);
    if (node.uniqueItems === true && new Set(list.map((v) => JSON.stringify(v))).size !== list.length) problems.push(`${at}: repeated items`);
    if (node.items) list.forEach((item, i) => problems.push(...validate(node.items as Node, item, `${at}[${i}]`)));
  }
  if (type === "object") {
    const object = value as Record<string, unknown>;
    for (const key of (node.required as string[] | undefined) ?? []) {
      if (!(key in object)) problems.push(`${at}: missing ${key}`);
    }
    const properties = (node.properties as Record<string, Node> | undefined) ?? {};
    for (const [key, child] of Object.entries(object)) {
      if (properties[key]) problems.push(...validate(properties[key], child, `${at}.${key}`));
      else if (node.additionalProperties === false) problems.push(`${at}: unexpected ${key}`);
    }
  }
  return problems;
}
