/*
 * Port of RecapShareImage: the weekly recap drawn as an image to post: the
 * pet, the warm line, the hours focused, the week's bars and numbers,
 * signed with the Tabbi brand and tabbinotch.com. Laid out for one
 * `RecapShareFormat` in points and drawn on a canvas at
 * `RECAP_SHARE_SCALE`, in the theme's colors on the island's black, so the
 * card and its image match. Nothing leaves the machine: the PNG is copied
 * or saved by `recapSharing`.
 */

import { durationMinutes } from "../../../core/formatting/durationFormat";
import { tr } from "../../../core/localization/tr";
import type { PetProfile } from "../../../core/pets/petProfile";
import { recapDayInitials, recapStats, recapWeekTitle } from "../../../core/recap/recapStats";
import { RECAP_SHARE_BRAND, RECAP_SHARE_SCALE, RECAP_SHARE_WEBSITE, recapSharePointSize, type RecapShareFormat } from "../../../core/recap/recapShareFormat";
import { recapCheerLine, type RecapCheer, type WeeklyRecap } from "../../../core/recap/weeklyRecap";
import type { AppTheme } from "../../../core/themes/appTheme";
import { drawPet } from "../../../ui/pets/drawPet";
import { themeAccent } from "../../../core/themes/appTheme";
import { cssColor, cssColorAt, FONT_DISPLAY, FONT_TEXT, Spacing } from "../../../ui/kit/tokens";
import { CLOSET_ACCENT } from "../closetDescriptor";
import { barHeight } from "./RecapCard";

export interface RecapShareInput {
  readonly recap: WeeklyRecap;
  readonly cheer: RecapCheer;
  /** The user's pet as it looks now; undefined when the pet is turned off. */
  readonly pet: PetProfile | undefined;
  readonly format: RecapShareFormat;
  readonly theme: AppTheme;
  readonly locale: string;
  readonly timeZone: string;
}

/** A drawing context the image needs; the canvas 2D context has it, and tests can hand in a stand-in. */
export type ShareContext = CanvasRenderingContext2D;

interface Palette {
  readonly background: string;
  readonly surface: string;
  readonly stroke: string;
  readonly primary: string;
  readonly secondary: string;
  readonly tertiary: string;
  readonly accent: string;
  readonly accentSoft: string;
}

function palette(theme: AppTheme): Palette {
  const accent = themeAccent(theme, CLOSET_ACCENT);
  return {
    background: cssColor(theme.palette.background),
    surface: cssColor(theme.palette.surface),
    stroke: cssColor(theme.palette.stroke),
    primary: cssColor(theme.palette.primaryText),
    secondary: cssColor(theme.palette.secondaryText),
    tertiary: cssColor(theme.palette.tertiaryText),
    accent: cssColor(accent),
    accentSoft: cssColorAt(accent, 0.22),
  };
}

function font(size: number, weight: number, display = false): string {
  return `${weight} ${size}px ${display ? FONT_DISPLAY : FONT_TEXT}`;
}

/* Lines of `text` that fit `width` at `fontSpec`, breaking at spaces and inside a word only when it is wider than the line on its own. */
function wrap(context: ShareContext, text: string, fontSpec: string, width: number): string[] {
  context.font = fontSpec;
  const fits = (candidate: string) => context.measureText(candidate).width <= width;
  const lines: string[] = [];
  let line = "";
  const push = (word: string) => {
    const joined = line === "" ? word : `${line} ${word}`;
    if (fits(joined)) {
      line = joined;
      return;
    }
    if (line !== "") lines.push(line);
    line = "";
    if (fits(word)) {
      line = word;
      return;
    }
    for (const character of word) {
      if (fits(line + character)) line += character;
      else {
        if (line !== "") lines.push(line);
        line = character;
      }
    }
  };
  for (const word of text.split(/\s+/).filter((part) => part !== "")) push(word);
  if (line !== "") lines.push(line);
  return lines;
}

/* The largest size down to `minimum` at which `text` wraps into at most `maxLines`, with its lines. */
function fitText(context: ShareContext, text: string, size: number, weight: number, width: number, maxLines: number, minimumScale: number): { size: number; lines: string[] } {
  for (let scale = 1; scale >= minimumScale - 1e-9; scale -= 0.05) {
    const candidate = size * scale;
    const lines = wrap(context, text, font(candidate, weight), width);
    if (lines.length <= maxLines) return { size: candidate, lines };
  }
  const lines = wrap(context, text, font(size * minimumScale, weight), width).slice(0, maxLines);
  return { size: size * minimumScale, lines };
}

/* A four-point sparkle, the share image's brand mark, centered at (x, y) with radius r. */
function sparkle(context: ShareContext, x: number, y: number, r: number, color: string): void {
  const inner = r * 0.3;
  context.beginPath();
  context.moveTo(x, y - r);
  context.quadraticCurveTo(x + inner, y - inner, x + r, y);
  context.quadraticCurveTo(x + inner, y + inner, x, y + r);
  context.quadraticCurveTo(x - inner, y + inner, x - r, y);
  context.quadraticCurveTo(x - inner, y - inner, x, y - r);
  context.closePath();
  context.fillStyle = color;
  context.fill();
}

function roundedRect(context: ShareContext, x: number, y: number, width: number, height: number, radius: number): void {
  const r = Math.min(radius, width / 2, height / 2);
  context.beginPath();
  context.moveTo(x + r, y);
  context.arcTo(x + width, y, x + width, y + height, r);
  context.arcTo(x + width, y + height, x, y + height, r);
  context.arcTo(x, y + height, x, y, r);
  context.arcTo(x, y, x + width, y, r);
  context.closePath();
}

/** The pet sitting in its outfit as an image of `pixelSize` points per sprite pixel, for `drawImage`; undefined where no canvas can be made. */
function petImage(pet: PetProfile, pixelSize: number): HTMLCanvasElement | undefined {
  if (typeof document === "undefined") return undefined;
  const sprite = pet.sittingCanvas();
  const scale = Math.max(1, Math.round(pixelSize * RECAP_SHARE_SCALE));
  const element = document.createElement("canvas");
  element.width = sprite.width * scale;
  element.height = sprite.height * scale;
  const context = element.getContext("2d");
  if (!context) return undefined;
  drawPet(context, sprite, pet.palette, scale);
  return element;
}

/**
 * Draws the image onto `context`, whose canvas is the format's pixel size.
 * Everything is laid out in points and scaled once, so the layout reads
 * like the Mac's.
 */
export function drawRecapShareImage(context: ShareContext, input: RecapShareInput): void {
  const { recap, cheer, pet, format, locale, timeZone } = input;
  const colors = palette(input.theme);
  const size = recapSharePointSize(format);
  const isStory = format === "story";
  const padding = isStory ? 32 : Spacing.xl;
  const inner = size.width - 2 * padding;
  context.setTransform(RECAP_SHARE_SCALE, 0, 0, RECAP_SHARE_SCALE, 0, 0);
  context.imageSmoothingEnabled = false;
  context.textBaseline = "alphabetic";

  /* Black like the island, warming to gold at the bottom. */
  context.fillStyle = colors.background;
  context.fillRect(0, 0, size.width, size.height);
  const glow = context.createRadialGradient(size.width / 2, size.height, 0, size.width / 2, size.height, size.height * 0.8);
  glow.addColorStop(0, colors.accentSoft);
  glow.addColorStop(1, "rgb(0 0 0 / 0)");
  context.fillStyle = glow;
  context.fillRect(0, 0, size.width, size.height);

  /* Measure every block first, then spread what is left between them, as the Mac's spacers do. */
  const headerHeight = 19;
  const cheerFit = fitText(context, recapCheerLine(cheer), isStory ? 22 : 17, 600, isStory ? inner : inner - 96 - Spacing.l, 2, 0.8);
  const cheerHeight = cheerFit.lines.length * cheerFit.size * 1.2;
  const hoursSize = isStory ? 48 : 34;
  const hoursHeight = hoursSize * 1.15 + Spacing.xxs + 14;
  const heroHeight = isStory ? 32 * 5 + Spacing.m + cheerHeight + Spacing.m + hoursHeight : Math.max(96, cheerHeight + Spacing.xs + hoursHeight);
  const barMax = isStory ? 72 : 40;
  const daysHeight = Spacing.m * 2 + barMax + Spacing.xs + 9;
  const stats = recapStats(recap, locale);
  const statRows = Math.ceil(stats.length / 3);
  const statsHeight = statRows === 0 ? 0 : statRows * (17 * 1.2 + Spacing.xxs + 12) + (statRows - 1) * Spacing.m;
  const websiteHeight = 13;
  const blocks = [headerHeight, heroHeight, daysHeight, statsHeight, websiteHeight];
  const content = blocks.reduce((sum, height) => sum + height, 0);
  const gap = Math.max(Spacing.m, (size.height - 2 * padding - content) / (blocks.length - 1));
  let y = padding;

  /* Header: the brand on the left, the week's dates on the right. */
  sparkle(context, padding + 7, y + 10, 7, colors.accent);
  context.fillStyle = colors.primary;
  context.font = font(16, 700, true);
  context.textAlign = "left";
  context.fillText(RECAP_SHARE_BRAND, padding + 14 + Spacing.s, y + 15);
  context.fillStyle = colors.secondary;
  context.font = font(12, 500);
  context.textAlign = "right";
  context.fillText(recapWeekTitle(recap.week, locale, timeZone), size.width - padding, y + 14);
  y += headerHeight + gap;

  /* Hero: the pet beside (square) or over (story) the line and the hours. */
  const hoursText = durationMinutes(recap.focusMinutes);
  const hoursCaption = pet === undefined ? tr("focused this week") : tr("focused with %@", pet.name);
  const drawPetOrSparkles = (x: number, top: number, pixelSize: number) => {
    const side = 32 * pixelSize;
    const image = pet === undefined ? undefined : petImage(pet, pixelSize);
    if (image !== undefined) context.drawImage(image, x, top, side, side);
    else sparkle(context, x + side / 2, top + side / 2, 14 * pixelSize * 0.5, colors.accent);
  };
  const drawCheer = (x: number, top: number, align: CanvasTextAlign) => {
    context.fillStyle = colors.primary;
    context.font = font(cheerFit.size, 600);
    context.textAlign = align;
    cheerFit.lines.forEach((line, index) => context.fillText(line, x, top + cheerFit.size * (1 + 1.2 * index)));
  };
  const drawHours = (x: number, top: number, align: CanvasTextAlign) => {
    context.fillStyle = colors.accent;
    context.font = font(hoursSize, 700, true);
    context.textAlign = align;
    context.fillText(hoursText, x, top + hoursSize);
    context.fillStyle = colors.secondary;
    context.font = font(12, 500);
    context.fillText(hoursCaption, x, top + hoursSize * 1.15 + Spacing.xxs + 12);
  };
  if (isStory) {
    const center = size.width / 2;
    drawPetOrSparkles(center - 80, y, 5);
    drawCheer(center, y + 160 + Spacing.m, "center");
    drawHours(center, y + 160 + Spacing.m + cheerHeight + Spacing.m, "center");
  } else {
    const textTop = y + (heroHeight - (cheerHeight + Spacing.xs + hoursHeight)) / 2;
    drawPetOrSparkles(padding, y + (heroHeight - 96) / 2, 3);
    drawCheer(padding + 96 + Spacing.l, textTop, "left");
    drawHours(padding + 96 + Spacing.l, textTop + cheerHeight + Spacing.xs, "left");
  }
  y += heroHeight + gap;

  /* The days card: one bar per day, Monday first, the best in full accent. */
  roundedRect(context, padding, y, inner, daysHeight, 10);
  context.fillStyle = colors.surface;
  context.fill();
  context.strokeStyle = colors.stroke;
  context.lineWidth = 0.5;
  context.stroke();
  const barWidth = isStory ? 18 : 14;
  const barGap = isStory ? Spacing.l : Spacing.m;
  const barsWidth = 7 * barWidth + 6 * barGap;
  const best = Math.max(0, ...recap.minutesByDay);
  const initials = recapDayInitials(locale);
  const baseline = y + Spacing.m + barMax;
  recap.minutesByDay.forEach((minutes, index) => {
    const x = padding + (inner - barsWidth) / 2 + index * (barWidth + barGap);
    const height = barHeight(minutes, best, barMax);
    const isBest = best > 0 && minutes === best;
    roundedRect(context, x, baseline - height, barWidth, height, 3);
    context.fillStyle = isBest ? colors.accent : minutes > 0 ? cssColorAt(themeAccent(input.theme, CLOSET_ACCENT), 0.4) : colors.stroke;
    context.fill();
    context.fillStyle = isBest ? colors.secondary : colors.tertiary;
    context.font = font(9, 600);
    context.textAlign = "center";
    context.fillText(initials[index] ?? "", x + barWidth / 2, baseline + Spacing.xs + 8);
  });
  y += daysHeight + gap;

  /* The week's other numbers, three to a row, so none is dropped; a short last row stays centered on the same column width. */
  const column = inner / 3;
  for (let row = 0; row < statRows; row++) {
    const rowStats = stats.slice(row * 3, row * 3 + 3);
    const left = padding + (inner - rowStats.length * column) / 2;
    rowStats.forEach((stat, index) => {
      const x = left + column * (index + 0.5);
      context.textAlign = "center";
      context.fillStyle = colors.primary;
      context.font = font(17, 600);
      context.fillText(stat.value, x, y + 17);
      context.fillStyle = colors.tertiary;
      context.font = font(10.5, 500);
      context.fillText(stat.label, x, y + 17 * 1.2 + Spacing.xxs + 10);
    });
    y += 17 * 1.2 + Spacing.xxs + 12 + Spacing.m;
  }
  if (statRows > 0) y -= Spacing.m;
  y += statsHeight === 0 ? 0 : gap;

  /* Signed with the website. */
  context.fillStyle = colors.tertiary;
  context.font = font(11, 500);
  context.textAlign = "center";
  context.fillText(RECAP_SHARE_WEBSITE, size.width / 2, Math.min(y + 11, size.height - padding));
  context.setTransform(1, 0, 0, 1, 0, 0);
}

/** The image as a PNG blob at the format's full pixel size, drawn on a canvas of its own. */
export async function recapSharePNG(input: RecapShareInput): Promise<Blob> {
  const pixels = recapSharePointSize(input.format);
  const element = document.createElement("canvas");
  element.width = pixels.width * RECAP_SHARE_SCALE;
  element.height = pixels.height * RECAP_SHARE_SCALE;
  const context = element.getContext("2d");
  if (!context) throw new Error("The recap image needs a canvas");
  drawRecapShareImage(context, input);
  return new Promise((resolve, reject) => {
    element.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("The recap image could not be encoded"))), "image/png");
  });
}
