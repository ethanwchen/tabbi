import { tr } from "../localization/tr";
import { StudyMethod } from "./studyMethod";
import { studyMethodDefinitions as file } from "./studyMethodDefinitions";
import {
  STUDY_METHOD_KINDS,
  type StudyEvidenceLevel,
  type StudyMethodFileMethod,
  type StudyMethodKind,
} from "./studyMethodFile";

export { STUDY_EVIDENCE_LEVELS, type StudyEvidenceLevel } from "./studyMethodFile";

/*
 * `study-methods.json` stays English, since both apps read it, so the copy is
 * translated through the catalog by that English text, as on the Mac.
 */
function localized(text: string): string {
  return tr(text);
}

/** Port of StudyEvidenceLevel.label: the badge text in the user's language. */
export function evidenceLevelLabel(level: StudyEvidenceLevel): string {
  return localized(file.evidenceLevels[level]);
}

/**
 * Port of StudyMethodInfo: copy for a study method's info popover, what it
 * is, how to do it, and an honest note on the evidence. Deliberately modest:
 * what research supports is regular breaks, self-testing and spacing, not
 * any particular interval length.
 */
export class StudyMethodInfo {
  readonly kind: StudyMethodKind;
  readonly name: string;
  /** One-line description for the method picker. */
  readonly tagline: string;
  /** Plain-language instructions, 2 to 3 sentences. */
  readonly howTo: string;
  /** One or two sentences on what the evidence does and does not show. */
  readonly evidence: string;
  /** The badge rating, or undefined for a plain tool that is not a study method (the Timer). */
  readonly evidenceLevel: StudyEvidenceLevel | undefined;

  constructor(entry: StudyMethodFileMethod) {
    this.kind = entry.kind;
    this.name = entry.name;
    this.tagline = entry.tagline;
    this.howTo = entry.howTo;
    this.evidence = entry.evidence;
    this.evidenceLevel = entry.evidenceLevel;
  }

  /** The name in the user's language. */
  get displayName(): string {
    return localized(this.name);
  }

  /** The tagline in the user's language. */
  get displayTagline(): string {
    return localized(this.tagline);
  }

  /**
   * `howTo` cut after its first sentence, its first two, and so on up to the
   * whole text, so a small card can show as many whole sentences as fit.
   */
  get howToSentencePrefixes(): string[] {
    const sentences = this.howTo.split(". ");
    return sentences.map((_, end) => {
      const prefix = sentences.slice(0, end + 1).join(". ");
      return end === sentences.length - 1 ? prefix : `${prefix}.`;
    });
  }

  /** Shared footnote under every popover. */
  static readonly footnote: string = file.footnote;

  /** The copy the file gives `kind`; the file defines every kind. */
  static info(kind: StudyMethodKind): StudyMethodInfo {
    const found = BY_KIND.get(kind) ?? FIRST;
    return found;
  }

  /** Info for every method, in `StudyMethodKind` order. */
  static get all(): StudyMethodInfo[] {
    return STUDY_METHOD_KINDS.map((kind) => StudyMethodInfo.info(kind));
  }
}

const BY_KIND = new Map<StudyMethodKind, StudyMethodInfo>(file.methods.map((entry) => [entry.kind, new StudyMethodInfo(entry)]));
const FIRST = (() => {
  const entry = file.methods[0];
  if (entry === undefined) throw new Error("study-methods.json has no methods");
  return new StudyMethodInfo(entry);
})();

/** Port of StudyMethod.info: popover copy for this method's kind. */
export function methodInfo(method: StudyMethod): StudyMethodInfo {
  return StudyMethodInfo.info(method.kind);
}

/**
 * Port of StudyMethod.nameIsRhythm: whether the method's name already spells
 * out its rhythm ("52 / 17"), so views show the name alone.
 */
export function nameIsRhythm(method: StudyMethod): boolean {
  return methodInfo(method).name.replaceAll(" ", "") === method.rhythmLabel;
}
