import { PET_PALETTE_ROLES, roleAt, roleFromSymbol, roleIndex, roleSymbol, type PetPaletteRole } from "./petPalette";

/*
 * Port of PetPatternZone, SpriteCell and SpriteGrid: text-drawn sprite
 * layers in the legend of docs/study/pets.md.
 *
 * Cells are stored as small integers so composing thousands of frames stays
 * fast: 0 is transparent, 1 erases, `ROLE_CELL + role index` paints a role
 * and `ZONE_CELL + zone index` paints a breed pattern zone.
 */

/** Breed-dependent regions inside shared body art, in the Mac's declaration order. */
export const PET_PATTERN_ZONES = [
  "muzzle",
  "chest",
  "paws",
  "tailTip",
  "ears",
  "mask",
  "stripes",
  "patchA",
  "patchB",
] as const;

export type PetPatternZone = (typeof PET_PATTERN_ZONES)[number];

const ZONE_SYMBOLS = "mcptefsab";

export function zoneSymbol(zone: PetPatternZone): string {
  return ZONE_SYMBOLS.charAt(PET_PATTERN_ZONES.indexOf(zone));
}

export function zoneFromSymbol(symbol: string): PetPatternZone | undefined {
  const index = symbol.length === 1 ? ZONE_SYMBOLS.indexOf(symbol) : -1;
  return index < 0 ? undefined : PET_PATTERN_ZONES[index];
}

export function isPetPatternZone(value: string): value is PetPatternZone {
  return (PET_PATTERN_ZONES as readonly string[]).includes(value);
}

/** What a zone looks like when a breed says nothing about it: plain fur with a lighter muzzle and chest. */
export function zoneDefaultRole(zone: PetPatternZone): PetPaletteRole {
  return zone === "muzzle" || zone === "chest" ? "belly" : "furBase";
}

/** One cell of a sprite grid. Port of SpriteCell. */
export type SpriteCell =
  | { readonly kind: "empty" }
  | { readonly kind: "erase" }
  | { readonly kind: "role"; readonly role: PetPaletteRole }
  | { readonly kind: "zone"; readonly zone: PetPatternZone };

export const EMPTY_CELL = 0;
export const ERASE_CELL = 1;
export const ROLE_CELL = 2;
export const ZONE_CELL = ROLE_CELL + PET_PALETTE_ROLES.length;

/** The cell code painting `role`. */
export function roleCell(role: PetPaletteRole): number {
  return ROLE_CELL + roleIndex(role);
}

/** The cell code painting `zone`. */
export function zoneCell(zone: PetPatternZone): number {
  return ZONE_CELL + PET_PATTERN_ZONES.indexOf(zone);
}

export function cellFromCode(code: number): SpriteCell {
  if (code === EMPTY_CELL) return { kind: "empty" };
  if (code === ERASE_CELL) return { kind: "erase" };
  if (code < ZONE_CELL) return { kind: "role", role: roleAt(code - ROLE_CELL) };
  return { kind: "zone", zone: PET_PATTERN_ZONES[code - ZONE_CELL] ?? "muzzle" };
}

/** The code for a grid character, or undefined for an unknown symbol. */
export function cellCodeFromSymbol(symbol: string): number | undefined {
  if (symbol === "." || symbol === " ") return EMPTY_CELL;
  if (symbol === "x") return ERASE_CELL;
  const role = roleFromSymbol(symbol);
  if (role) return roleCell(role);
  const zone = zoneFromSymbol(symbol);
  return zone ? zoneCell(zone) : undefined;
}

export function cellSymbol(code: number): string {
  const cell = cellFromCode(code);
  switch (cell.kind) {
    case "empty":
      return ".";
    case "erase":
      return "x";
    case "role":
      return roleSymbol(cell.role);
    case "zone":
      return zoneSymbol(cell.zone);
  }
}

export class SpriteGridParseError extends Error {}

/** Swift's `Character.isWhitespace` for the characters a text grid can hold. */
function isWhitespaceRow(row: string): boolean {
  return /^\s*$/u.test(row);
}

/**
 * A rectangular text-drawn sprite layer. Port of SpriteGrid: rows must all
 * be the same width so a typo can never silently shift the art.
 */
export class SpriteGrid {
  readonly width: number;
  readonly height: number;
  readonly cells: Uint8Array;

  constructor(width: number, height: number, cells?: Uint8Array) {
    this.width = width;
    this.height = height;
    this.cells = cells ?? new Uint8Array(width * height);
  }

  /** Parses a text grid; leading and trailing blank rows are ignored. Rows and columns in errors are 1-based. */
  static parse(text: string): SpriteGrid {
    const rows = text.split("\n");
    while (rows.length > 0 && isWhitespaceRow(rows[0] ?? "")) rows.shift();
    while (rows.length > 0 && isWhitespaceRow(rows[rows.length - 1] ?? "")) rows.pop();
    const first = rows[0];
    if (first === undefined) throw new SpriteGridParseError("Sprite grid has no rows");
    const width = [...first].length;
    const cells = new Uint8Array(width * rows.length);
    rows.forEach((row, rowIndex) => {
      const symbols = [...row];
      if (symbols.length !== width) {
        throw new SpriteGridParseError(`Row ${rowIndex + 1} is ${symbols.length} wide; expected ${width}`);
      }
      symbols.forEach((symbol, columnIndex) => {
        const code = cellCodeFromSymbol(symbol);
        if (code === undefined) {
          throw new SpriteGridParseError(
            `Unknown symbol '${symbol}' at row ${rowIndex + 1}, column ${columnIndex + 1}`,
          );
        }
        cells[rowIndex * width + columnIndex] = code;
      });
    });
    return new SpriteGrid(width, rows.length, cells);
  }

  /** Parses rows as the JSON art stores them. */
  static fromRows(rows: readonly string[]): SpriteGrid {
    return SpriteGrid.parse(rows.join("\n"));
  }

  /** The cell code at (x, y). */
  code(x: number, y: number): number {
    return this.cells[y * this.width + x] ?? EMPTY_CELL;
  }

  cell(x: number, y: number): SpriteCell {
    return cellFromCode(this.code(x, y));
  }

  setCode(x: number, y: number, code: number): void {
    this.cells[y * this.width + x] = code;
  }

  copy(): SpriteGrid {
    return new SpriteGrid(this.width, this.height, this.cells.slice());
  }

  /** Left-right mirror, for facing the other way. */
  mirrored(): SpriteGrid {
    const copy = new SpriteGrid(this.width, this.height);
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) copy.setCode(x, y, this.code(this.width - 1 - x, y));
    }
    return copy;
  }

  /** The grid written back out as text, one row per line. */
  get text(): string {
    const rows: string[] = [];
    for (let y = 0; y < this.height; y++) {
      let row = "";
      for (let x = 0; x < this.width; x++) row += cellSymbol(this.code(x, y));
      rows.push(row);
    }
    return rows.join("\n");
  }

  equals(other: SpriteGrid): boolean {
    if (this.width !== other.width || this.height !== other.height) return false;
    for (let i = 0; i < this.cells.length; i++) if (this.cells[i] !== other.cells[i]) return false;
    return true;
  }
}
