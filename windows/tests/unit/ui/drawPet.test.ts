import { describe, expect, it } from "vitest";
import { breedPalette } from "../../../src/core/pets/petBreed";
import { PetCanvas } from "../../../src/core/pets/petCanvas";
import { renderPet } from "../../../src/core/pets/petRenderer";
import { drawPet, pixelScale, type PetDrawingContext } from "../../../src/ui/pets/drawPet";

describe("pixelScale", () => {
  it("picks the largest whole device-pixel scale that fits the box", () => {
    expect(pixelScale(64, 64, 1).scale).toBe(2);
    expect(pixelScale(70, 64, 1).scale).toBe(2);
    expect(pixelScale(95, 95, 1).scale).toBe(2);
    expect(pixelScale(96, 96, 1).scale).toBe(3);
    expect(pixelScale(64, 64, 2).scale).toBe(4);
  });

  it("never gives 125 or 150 percent displays uneven pixels", () => {
    for (const ratio of [1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3]) {
      for (const box of [24, 32, 40, 48, 56, 64, 72, 80, 96, 128]) {
        const size = pixelScale(box, box, ratio);
        expect(Number.isInteger(size.scale)).toBe(true);
        expect(size.deviceWidth).toBe(32 * size.scale);
        // The CSS size maps back onto exactly the backing store, so no resampling happens.
        expect(size.cssWidth * ratio).toBeCloseTo(size.deviceWidth, 9);
        // And it never spills out of the box.
        expect(size.cssWidth).toBeLessThanOrEqual(box + 1e-9);
      }
    }
  });

  it("fills a box that is an exact multiple at fractional scales", () => {
    // 32 CSS px at 150 percent is exactly 48 device px: a scale of 1.5 is not allowed, 1 is the largest whole one.
    expect(pixelScale(32, 32, 1.5)).toEqual({
      scale: 1,
      deviceWidth: 32,
      deviceHeight: 32,
      cssWidth: 32 / 1.5,
      cssHeight: 32 / 1.5,
    });
    // 64 CSS px at 150 percent is 96 device px: three device pixels per sprite pixel, the whole box.
    const exact = pixelScale(64, 64, 1.5);
    expect(exact.scale).toBe(3);
    expect(exact.cssWidth).toBeCloseTo(64, 9);
    // 51.2 CSS px at 125 percent is exactly 64 device px, despite the floating point product.
    expect(pixelScale(51.2, 51.2, 1.25).scale).toBe(2);
  });

  it("uses the smaller side and the sprite's own size", () => {
    expect(pixelScale(200, 64, 1).scale).toBe(2);
    expect(pixelScale(64, 200, 1, 16, 32).scale).toBe(4);
  });

  it("gives zero when nothing fits and treats a bad ratio as 1", () => {
    expect(pixelScale(20, 20, 1).scale).toBe(0);
    expect(pixelScale(-5, 40, 1).scale).toBe(0);
    expect(pixelScale(64, 64, 0).scale).toBe(2);
    expect(pixelScale(64, 64, Number.NaN).scale).toBe(2);
  });
});

describe("drawPet", () => {
  class Recorder implements PetDrawingContext {
    imageSmoothingEnabled = true;
    puts: { data: ImageData; x: number; y: number }[] = [];

    createImageData(width: number, height: number): ImageData {
      return { width, height, data: new Uint8ClampedArray(width * height * 4), colorSpace: "srgb" } as ImageData;
    }

    putImageData(data: ImageData, x: number, y: number): void {
      this.puts.push({ data, x, y });
    }
  }

  const canvas = new PetCanvas(2, 1);
  canvas.setRole(0, 0, "furBase");
  const palette = breedPalette("orangeTabby");

  it("turns smoothing off and writes every sprite pixel as a whole block", () => {
    const context = new Recorder();
    drawPet(context, canvas, palette, 3, 4.4, 5.6);
    expect(context.imageSmoothingEnabled).toBe(false);
    const put = context.puts[0];
    expect(put?.x).toBe(4);
    expect(put?.y).toBe(6);
    expect(put?.data.width).toBe(6);
    expect(put?.data.height).toBe(3);
    expect(put?.data.data).toEqual(renderPet(canvas, palette, 3).data);
    const fur = palette.color("furBase");
    // Row 2, column 2 is still the fur block; column 3 starts the transparent one.
    const at = (x: number, y: number) => [...(put?.data.data.slice((y * 6 + x) * 4, (y * 6 + x) * 4 + 4) ?? [])];
    expect(at(2, 2)).toEqual([fur.red, fur.green, fur.blue, 255]);
    expect(at(3, 2)).toEqual([0, 0, 0, 0]);
  });

  it("draws nothing below a whole pixel", () => {
    const context = new Recorder();
    drawPet(context, canvas, palette, 0.9);
    expect(context.puts).toEqual([]);
    expect(context.imageSmoothingEnabled).toBe(false);
  });
});
