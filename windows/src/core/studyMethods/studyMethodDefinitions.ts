import bundled from "@mac/StudyMethods/study-methods.json";
import { decodeStudyMethodFile, type StudyMethodFile } from "./studyMethodFile";

/**
 * Port of StudyMethodDefinitions: the bundled `study-methods.json`, read once
 * from the Mac's own copy. `StudyMethod`, `StudyMethodInfo`,
 * `StudyTimerLength` and `StudyCustomRhythm` take their defaults from here.
 * It ships with the app, so a broken file throws at load (and fails CI)
 * rather than running timers on made-up lengths.
 */
export const studyMethodDefinitions: StudyMethodFile = decodeStudyMethodFile(bundled);
