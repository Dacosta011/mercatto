export type FormationId = "4-3-3" | "4-4-2" | "4-2-3-1" | "3-5-2";

export interface FormationSlot {
  id: string;
  label: string;
  x: number;
  y: number;
  compatiblePositions: string[];
}

export interface Formation {
  id: FormationId;
  label: string;
  slots: FormationSlot[];
}

const formations: Record<FormationId, Formation> = {
  "4-3-3": {
    id: "4-3-3",
    label: "4-3-3",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",  label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1", label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",  label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "cm1", label: "MC",  x: 27, y: 47, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 50, y: 43, compatiblePositions: ["MC", "CM", "MCO", "CAM"] },
      { id: "cm3", label: "MC",  x: 73, y: 47, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "lw",  label: "EI",  x: 16, y: 22, compatiblePositions: ["EI", "LW", "LM", "MI"] },
      { id: "st",  label: "DC",  x: 50, y: 12, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
      { id: "rw",  label: "ED",  x: 84, y: 22, compatiblePositions: ["ED", "RW", "RM", "MD"] },
    ],
  },
  "4-4-2": {
    id: "4-4-2",
    label: "4-4-2",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",  label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1", label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",  label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "lm",  label: "MI",  x: 14, y: 47, compatiblePositions: ["MI", "LM", "EI", "LW"] },
      { id: "cm1", label: "MC",  x: 38, y: 49, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 62, y: 49, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "rm",  label: "MD",  x: 86, y: 47, compatiblePositions: ["MD", "RM", "ED", "RW"] },
      { id: "st1", label: "DC",  x: 38, y: 17, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
      { id: "st2", label: "DC",  x: 62, y: 17, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },
  "4-2-3-1": {
    id: "4-2-3-1",
    label: "4-2-3-1",
    slots: [
      { id: "gk",   label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",   label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1",  label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2",  label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",   label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "cdm1", label: "MCD", x: 36, y: 55, compatiblePositions: ["MCD", "CDM", "MC", "CM"] },
      { id: "cdm2", label: "MCD", x: 64, y: 55, compatiblePositions: ["MCD", "CDM", "MC", "CM"] },
      { id: "lw",   label: "EI",  x: 16, y: 34, compatiblePositions: ["EI", "LW", "LM", "MI"] },
      { id: "cam",  label: "MCO", x: 50, y: 32, compatiblePositions: ["MCO", "CAM", "MC", "CM", "SD", "SS"] },
      { id: "rw",   label: "ED",  x: 84, y: 34, compatiblePositions: ["ED", "RW", "RM", "MD"] },
      { id: "st",   label: "DC",  x: 50, y: 12, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },
  "3-5-2": {
    id: "3-5-2",
    label: "3-5-2",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "cb1", label: "DFC", x: 22, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 50, y: 77, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb3", label: "DFC", x: 78, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "lwb", label: "MI",  x: 10, y: 52, compatiblePositions: ["MI", "LM", "LI", "LB", "LWB", "EI", "LW"] },
      { id: "cm1", label: "MC",  x: 30, y: 48, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 50, y: 44, compatiblePositions: ["MC", "CM", "MCO", "CAM"] },
      { id: "cm3", label: "MC",  x: 70, y: 48, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "rwb", label: "MD",  x: 90, y: 52, compatiblePositions: ["MD", "RM", "LD", "RB", "RWB", "ED", "RW"] },
      { id: "st1", label: "DC",  x: 36, y: 17, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
      { id: "st2", label: "DC",  x: 64, y: 17, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },
};

export const FORMATION_IDS: FormationId[] = ["4-3-3", "4-4-2", "4-2-3-1", "3-5-2"];
export default formations;
