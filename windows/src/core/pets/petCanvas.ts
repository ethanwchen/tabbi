import {
  DARK_MOUTH_BACKGROUND,
  PET_PALETTE_ROLES,
  luminance,
  roleAt,
  roleIndex,
  roleSymbol,
  type PetColor,
  type PetPalette,
  type PetPaletteRole,
} from "./petPalette";
import {
  EMPTY_CELL,
  ERASE_CELL,
  PET_PATTERN_ZONES,
  ROLE_CELL,
  ZONE_CELL,
  zoneDefaultRole,
  type PetPatternZone,
  type SpriteGrid,
} from "./spriteGrid";

/** A stamp table entry that leaves the canvas pixel alone. */
const SKIP = 255;

/**
 * How a breed colors the pattern zones of shared art; zones not listed use
 * their default role. Port of PetPattern.
 */
export class PetPattern {
  readonly zones: Partial<Record<PetPatternZone, PetPaletteRole>>;
  /** Cell code to canvas pixel (`SKIP` for transparent cells). */
  readonly stampTable: Uint8Array;

  constructor(zones: Partial<Record<PetPatternZone, PetPaletteRole>> = {}) {
    this.zones = zones;
    const table = new Uint8Array(ZONE_CELL + PET_PATTERN_ZONES.length);
    table[EMPTY_CELL] = SKIP;
    table[ERASE_CELL] = 0;
    for (let i = 0; i < PET_PALETTE_ROLES.length; i++) table[ROLE_CELL + i] = i + 1;
    PET_PATTERN_ZONES.forEach((zone, i) => {
      table[ZONE_CELL + i] = roleIndex(this.role(zone)) + 1;
    });
    this.stampTable = table;
  }

  role(zone: PetPatternZone): PetPaletteRole {
    return this.zones[zone] ?? zoneDefaultRole(zone);
  }

  static readonly plain = new PetPattern();
}

/** A canvas pixel: 0 is transparent, otherwise the role's index plus one. */
export function pixelFor(role: PetPaletteRole | undefined): number {
  return role === undefined ? 0 : roleIndex(role) + 1;
}

const OUTLINE = pixelFor("outline");
const MOUTH = pixelFor("mouth");

/**
 * A frame being composed: a grid of palette roles. Layers are stamped in
 * order, so a later layer paints over an earlier one. Port of PetCanvas.
 */
export class PetCanvas {
  readonly width: number;
  readonly height: number;
  readonly pixels: Uint8Array;

  constructor(width: number, height: number, pixels?: Uint8Array) {
    this.width = width;
    this.height = height;
    this.pixels = pixels ?? new Uint8Array(width * height);
  }

  /** The role at (x, y), or undefined when transparent or outside the canvas. */
  role(x: number, y: number): PetPaletteRole | undefined {
    const pixel = this.pixel(x, y);
    return pixel === 0 ? undefined : roleAt(pixel - 1);
  }

  /** The raw pixel at (x, y), 0 outside the canvas. */
  pixel(x: number, y: number): number {
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return 0;
    return this.pixels[y * this.width + x] ?? 0;
  }

  setRole(x: number, y: number, role: PetPaletteRole | undefined): void {
    this.setPixel(x, y, pixelFor(role));
  }

  /** Sets a raw pixel; positions outside the canvas are ignored. */
  setPixel(x: number, y: number, pixel: number): void {
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return;
    this.pixels[y * this.width + x] = pixel;
  }

  copy(): PetCanvas {
    return new PetCanvas(this.width, this.height, this.pixels.slice());
  }

  /**
   * Paints `grid` with its top-left corner at (originX, originY). Pixels
   * outside the canvas are clipped, which is how the peek slides a pet in
   * from beyond the top edge.
   */
  stamp(grid: SpriteGrid, originX: number, originY: number, pattern: PetPattern = PetPattern.plain): void {
    const table = pattern.stampTable;
    const { width, height, pixels } = this;
    const gridWidth = grid.width;
    const cells = grid.cells;
    const x0 = Math.max(0, -originX);
    const x1 = Math.min(gridWidth, width - originX);
    const y0 = Math.max(0, -originY);
    const y1 = Math.min(grid.height, height - originY);
    for (let gy = y0; gy < y1; gy++) {
      const row = (originY + gy) * width + originX;
      const gridRow = gy * gridWidth;
      for (let gx = x0; gx < x1; gx++) {
        const value = table[cells[gridRow + gx] ?? 0] ?? SKIP;
        if (value !== SKIP) pixels[row + gx] = value;
      }
    }
  }

  /**
   * Adds a one-pixel `role` border around every opaque shape, using the four
   * direct neighbors only so corners stay rounded. Pixels with a role in
   * `except` grow no border.
   */
  outlined(role: PetPaletteRole = "outline", except: readonly PetPaletteRole[] = []): PetCanvas {
    const { width, height, pixels } = this;
    const result = this.copy();
    const out = result.pixels;
    const border = pixelFor(role);
    const skip = new Uint8Array(PET_PALETTE_ROLES.length + 1);
    skip[0] = 1;
    for (const exception of except) skip[pixelFor(exception)] = 1;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const index = y * width + x;
        if (pixels[index] !== 0) continue;
        if (
          (x > 0 && skip[pixels[index - 1] ?? 0] === 0) ||
          (x < width - 1 && skip[pixels[index + 1] ?? 0] === 0) ||
          (y > 0 && skip[pixels[index - width] ?? 0] === 0) ||
          (y < height - 1 && skip[pixels[index + width] ?? 0] === 0)
        ) {
          out[index] = border;
        }
      }
    }
    return result;
  }

  /** A copy moved by (dx, dy) pixels; whatever leaves the canvas is clipped. */
  shifted(dx: number, dy: number): PetCanvas {
    if (dx === 0 && dy === 0) return this;
    const { width, height, pixels } = this;
    const result = new PetCanvas(width, height);
    const out = result.pixels;
    for (let y = 0; y < height; y++) {
      const ty = y + dy;
      if (ty < 0 || ty >= height) continue;
      for (let x = 0; x < width; x++) {
        const tx = x + dx;
        if (tx < 0 || tx >= width) continue;
        out[ty * width + tx] = pixels[y * width + x] ?? 0;
      }
    }
    return result;
  }

  /** Upside-down copy, for a pet hanging out of the notch head first. */
  flippedVertically(): PetCanvas {
    const result = new PetCanvas(this.width, this.height);
    for (let y = 0; y < this.height; y++) {
      const from = y * this.width;
      result.pixels.set(this.pixels.subarray(from, from + this.width), (this.height - 1 - y) * this.width);
    }
    return result;
  }

  /** The smallest rectangle containing every opaque pixel, or undefined when empty. */
  get opaqueBounds(): { minX: number; minY: number; maxX: number; maxY: number } | undefined {
    let minX = this.width;
    let minY = this.height;
    let maxX = -1;
    let maxY = -1;
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) {
        if (this.pixels[y * this.width + x] === 0) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    return maxX < 0 ? undefined : { minX, minY, maxX, maxY };
  }

  /**
   * Resolves roles to colors, row-major, undefined for transparent pixels.
   * Mouth pixels take the rim color on dark fur, so one face works on a
   * white muzzle and a black cat alike.
   */
  colors(palette: PetPalette): (PetColor | undefined)[] {
    const { width, height, pixels } = this;
    const colors: (PetColor | undefined)[] = Array.from(pixels, (pixel) =>
      pixel === 0 ? undefined : palette.colorAt(pixel - 1),
    );
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        if (pixels[y * width + x] !== MOUTH) continue;
        const around = [this.pixel(x - 1, y), this.pixel(x + 1, y), this.pixel(x, y - 1), this.pixel(x, y + 1)]
          .filter((pixel) => pixel !== 0 && pixel !== MOUTH)
          .map((pixel) => luminance(palette.colorAt(pixel - 1)));
        if (around.length === 0) continue;
        if (around.reduce((sum, value) => sum + value, 0) / around.length < DARK_MOUTH_BACKGROUND) {
          colors[y * width + x] = palette.rim;
        }
      }
    }
    return colors;
  }

  /** The grid characters of every pixel, row-major (`.` for transparent). */
  symbols(): string {
    let out = "";
    for (const pixel of this.pixels) out += pixel === 0 ? "." : roleSymbol(roleAt(pixel - 1));
    return out;
  }

  /** Rows of grid characters, as the golden fixtures write a frame. */
  rows(): string[] {
    const all = this.symbols();
    const rows: string[] = [];
    for (let y = 0; y < this.height; y++) rows.push(all.slice(y * this.width, (y + 1) * this.width));
    return rows;
  }

  equals(other: PetCanvas): boolean {
    if (this.width !== other.width || this.height !== other.height) return false;
    const a = this.pixels;
    const b = other.pixels;
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
  }

  /** A copy whose transparent pixels show `layer` from behind. */
  over(layer: PetCanvas): PetCanvas {
    const result = this.copy();
    const out = result.pixels;
    const under = layer.pixels;
    for (let i = 0; i < out.length; i++) if (out[i] === 0) out[i] = under[i] ?? 0;
    return result;
  }

  /**
   * A copy with the particles of `layer` (8-connected groups) in the free
   * air: a particle that would cover or touch an opaque pixel is left out
   * whole, so petals never hide or brush the pet.
   */
  scattering(layer: PetCanvas): PetCanvas {
    const result = this.copy();
    const { width } = this;
    for (const particle of layer.particles()) {
      const clear = particle.every((index) => {
        const x = index % width;
        const y = (index - x) / width;
        return (
          this.pixel(x, y) === 0 &&
          this.pixel(x - 1, y) === 0 &&
          this.pixel(x + 1, y) === 0 &&
          this.pixel(x, y - 1) === 0 &&
          this.pixel(x, y + 1) === 0
        );
      });
      if (!clear) continue;
      for (const index of particle) result.pixels[index] = layer.pixels[index] ?? 0;
    }
    return result;
  }

  /** The particles (8-connected groups of opaque pixels), each as pixel indices. */
  particles(): number[][] {
    const { width, height, pixels } = this;
    const seen = new Uint8Array(pixels.length);
    const groups: number[][] = [];
    for (let start = 0; start < pixels.length; start++) {
      if (pixels[start] === 0 || seen[start]) continue;
      const particle: number[] = [];
      const queue = [start];
      seen[start] = 1;
      while (queue.length > 0) {
        const index = queue.pop() ?? 0;
        particle.push(index);
        const x = index % width;
        const y = (index - x) / width;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            const nx = x + dx;
            const ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            const neighbor = ny * width + nx;
            if (pixels[neighbor] === 0 || seen[neighbor]) continue;
            seen[neighbor] = 1;
            queue.push(neighbor);
          }
        }
      }
      groups.push(particle);
    }
    return groups;
  }

  /** The particles lying wholly at or below row `ceiling`; any that reach above it are left out whole. */
  keepingParticles(ceiling: number): PetCanvas {
    const kept = this.copy();
    for (const particle of this.particles()) {
      if (!particle.some((index) => Math.floor(index / this.width) < ceiling)) continue;
      for (const index of particle) kept.pixels[index] = 0;
    }
    return kept;
  }

  /** The pixels this canvas has where `base` is transparent: what was added over it. */
  added(base: PetCanvas): PetCanvas {
    const result = new PetCanvas(this.width, this.height);
    for (let i = 0; i < this.pixels.length; i++) {
      if (base.pixels[i] === 0) result.pixels[i] = this.pixels[i] ?? 0;
    }
    return result;
  }

  /** `over(layer)`, with an outline ring cut into `layer` around the pixels of `floating`. */
  overRinging(layer: PetCanvas, floating: PetCanvas): PetCanvas {
    const ringed = layer.copy();
    const { width, height } = this;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const index = y * width + x;
        if (floating.pixels[index] !== 0 || layer.pixels[index] === 0 || this.pixels[index] !== 0) continue;
        if (
          floating.pixel(x - 1, y) !== 0 ||
          floating.pixel(x + 1, y) !== 0 ||
          floating.pixel(x, y - 1) !== 0 ||
          floating.pixel(x, y + 1) !== 0
        ) {
          ringed.pixels[index] = OUTLINE;
        }
      }
    }
    return this.over(ringed);
  }

  /** A copy with an effect painted behind the pet (no outline): effect pixels only fill transparent space. */
  adding(grid: SpriteGrid, x: number, y: number): PetCanvas {
    const effect = new PetCanvas(this.width, this.height);
    effect.stamp(grid, x, y);
    return this.over(effect);
  }

  /** Paints the opaque pixels of `layer` over this canvas, moving each column down by `drop(x)`. */
  lay(layer: PetCanvas, drop: (x: number) => number): void {
    for (let x = 0; x < layer.width; x++) {
      const dy = drop(x);
      for (let y = 0; y < layer.height; y++) {
        const pixel = layer.pixels[y * layer.width + x] ?? 0;
        if (pixel !== 0) this.setPixel(x, y + dy, pixel);
      }
    }
  }
}
