import { radiantEligibleItems } from "../../src/core/pets/radiant/radiantResolver";
import { describeRadiantBudget } from "../support/radiantBudget";

/* Split in four so Vitest measures the costs on several workers at once. */
describeRadiantBudget(radiantEligibleItems().filter((_, index) => index % 4 === 0));
