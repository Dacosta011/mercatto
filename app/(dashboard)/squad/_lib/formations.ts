export type FormationId =
  | "4-3-3"
  | "4-4-2"
  | "4-2-3-1"
  | "3-5-2"
  | "4-2-1-3"
  | "4-4-1-1"
  | "4-2-2-2"
  | "4-3-2-1"
  | "4-1-2-1-2"
  | "5-2-1-2"
  | "3-4-3"
  | "3-4-2-1"
  | "4-1-4-1"
  | "4-5-1";

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

  // ── Existing ───────────────────────────────────────────────────────────────

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

  // ── FC 26 Meta formations ──────────────────────────────────────────────────

  // #1 meta en FC 26 - doble CDM, extremos y CAM
  "4-2-1-3": {
    id: "4-2-1-3",
    label: "4-2-1-3",
    slots: [
      { id: "gk",   label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",   label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1",  label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2",  label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",   label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "cdm1", label: "MCD", x: 36, y: 57, compatiblePositions: ["MCD", "CDM", "MC", "CM"] },
      { id: "cdm2", label: "MCD", x: 64, y: 57, compatiblePositions: ["MCD", "CDM", "MC", "CM"] },
      { id: "cam",  label: "MCO", x: 50, y: 40, compatiblePositions: ["MCO", "CAM", "MC", "CM", "SD", "SS"] },
      { id: "lw",   label: "EI",  x: 14, y: 20, compatiblePositions: ["EI", "LW", "LM", "MI"] },
      { id: "st",   label: "DC",  x: 50, y: 13, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
      { id: "rw",   label: "ED",  x: 86, y: 20, compatiblePositions: ["ED", "RW", "RM", "MD"] },
    ],
  },

  // Muy popular post-patch FC 26 - CAM y ST siempre arriba
  "4-4-1-1": {
    id: "4-4-1-1",
    label: "4-4-1-1",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",  label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1", label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",  label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "lm",  label: "MI",  x: 14, y: 49, compatiblePositions: ["MI", "LM", "EI", "LW"] },
      { id: "cm1", label: "MC",  x: 38, y: 51, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 62, y: 51, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "rm",  label: "MD",  x: 86, y: 49, compatiblePositions: ["MD", "RM", "ED", "RW"] },
      { id: "cam", label: "MCO", x: 50, y: 30, compatiblePositions: ["MCO", "CAM", "MC", "CM", "SD", "SS"] },
      { id: "st",  label: "DC",  x: 50, y: 13, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },

  // Doble CAM - muy ofensiva, popular en FC 26
  "4-2-2-2": {
    id: "4-2-2-2",
    label: "4-2-2-2",
    slots: [
      { id: "gk",   label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",   label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1",  label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2",  label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",   label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "cdm1", label: "MCD", x: 36, y: 56, compatiblePositions: ["MCD", "CDM", "MC", "CM"] },
      { id: "cdm2", label: "MCD", x: 64, y: 56, compatiblePositions: ["MCD", "CDM", "MC", "CM"] },
      { id: "cam1", label: "MCO", x: 30, y: 36, compatiblePositions: ["MCO", "CAM", "MC", "CM", "SD", "SS"] },
      { id: "cam2", label: "MCO", x: 70, y: 36, compatiblePositions: ["MCO", "CAM", "MC", "CM", "SD", "SS"] },
      { id: "st1",  label: "DC",  x: 36, y: 14, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
      { id: "st2",  label: "DC",  x: 64, y: 14, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },

  // 3 centros con dos "mediapuntas" - contraataque rápido
  "4-3-2-1": {
    id: "4-3-2-1",
    label: "4-3-2-1",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",  label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1", label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",  label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "cm1", label: "MC",  x: 22, y: 52, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 50, y: 50, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm3", label: "MC",  x: 78, y: 52, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "ss1", label: "SD",  x: 33, y: 28, compatiblePositions: ["SD", "SS", "MCO", "CAM", "DC", "ST"] },
      { id: "ss2", label: "SD",  x: 67, y: 28, compatiblePositions: ["SD", "SS", "MCO", "CAM", "DC", "ST"] },
      { id: "st",  label: "DC",  x: 50, y: 12, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },

  // Diamante estrecho - dominio del centro
  "4-1-2-1-2": {
    id: "4-1-2-1-2",
    label: "4-1-2-1-2",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",  label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1", label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",  label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "cdm", label: "MCD", x: 50, y: 59, compatiblePositions: ["MCD", "CDM", "MC", "CM"] },
      { id: "cm1", label: "MC",  x: 28, y: 46, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 72, y: 46, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cam", label: "MCO", x: 50, y: 33, compatiblePositions: ["MCO", "CAM", "MC", "CM", "SD", "SS"] },
      { id: "st1", label: "DC",  x: 33, y: 14, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
      { id: "st2", label: "DC",  x: 67, y: 14, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },

  // 5 defensas - muy sólida con dos delanteros
  "5-2-1-2": {
    id: "5-2-1-2",
    label: "5-2-1-2",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lwb", label: "LI",  x: 8,  y: 68, compatiblePositions: ["LI", "LB", "LWB", "MI", "LM"] },
      { id: "cb1", label: "DFC", x: 26, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 50, y: 77, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb3", label: "DFC", x: 74, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rwb", label: "LD",  x: 92, y: 68, compatiblePositions: ["LD", "RB", "RWB", "MD", "RM"] },
      { id: "cm1", label: "MC",  x: 33, y: 52, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 67, y: 52, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cam", label: "MCO", x: 50, y: 36, compatiblePositions: ["MCO", "CAM", "MC", "CM", "SD", "SS"] },
      { id: "st1", label: "DC",  x: 33, y: 14, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
      { id: "st2", label: "DC",  x: 67, y: 14, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },

  // 3 atrás muy ofensiva con 3 arriba
  "3-4-3": {
    id: "3-4-3",
    label: "3-4-3",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "cb1", label: "DFC", x: 22, y: 75, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 50, y: 78, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb3", label: "DFC", x: 78, y: 75, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "lm",  label: "MI",  x: 10, y: 52, compatiblePositions: ["MI", "LM", "LWB", "LI", "EI", "LW"] },
      { id: "cm1", label: "MC",  x: 34, y: 50, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 66, y: 50, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "rm",  label: "MD",  x: 90, y: 52, compatiblePositions: ["MD", "RM", "RWB", "LD", "ED", "RW"] },
      { id: "lw",  label: "EI",  x: 16, y: 18, compatiblePositions: ["EI", "LW", "LM", "MI", "SD", "SS"] },
      { id: "st",  label: "DC",  x: 50, y: 12, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
      { id: "rw",  label: "ED",  x: 84, y: 18, compatiblePositions: ["ED", "RW", "RM", "MD", "SD", "SS"] },
    ],
  },

  // 3 atrás con doble mediapunta y un 9
  "3-4-2-1": {
    id: "3-4-2-1",
    label: "3-4-2-1",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "cb1", label: "DFC", x: 22, y: 75, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 50, y: 78, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb3", label: "DFC", x: 78, y: 75, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "lm",  label: "MI",  x: 10, y: 53, compatiblePositions: ["MI", "LM", "LWB", "LI", "EI", "LW"] },
      { id: "cm1", label: "MC",  x: 34, y: 51, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 66, y: 51, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "rm",  label: "MD",  x: 90, y: 53, compatiblePositions: ["MD", "RM", "RWB", "LD", "ED", "RW"] },
      { id: "ss1", label: "SD",  x: 33, y: 28, compatiblePositions: ["SD", "SS", "MCO", "CAM", "EI", "LW"] },
      { id: "ss2", label: "SD",  x: 67, y: 28, compatiblePositions: ["SD", "SS", "MCO", "CAM", "ED", "RW"] },
      { id: "st",  label: "DC",  x: 50, y: 12, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },

  // Pivote único, 4 medios anchos, muy defensiva
  "4-1-4-1": {
    id: "4-1-4-1",
    label: "4-1-4-1",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",  label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1", label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",  label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "cdm", label: "MCD", x: 50, y: 58, compatiblePositions: ["MCD", "CDM", "MC", "CM"] },
      { id: "lm",  label: "MI",  x: 12, y: 43, compatiblePositions: ["MI", "LM", "EI", "LW"] },
      { id: "cm1", label: "MC",  x: 34, y: 45, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 66, y: 45, compatiblePositions: ["MC", "CM", "MCO", "CAM"] },
      { id: "rm",  label: "MD",  x: 88, y: 43, compatiblePositions: ["MD", "RM", "ED", "RW"] },
      { id: "st",  label: "DC",  x: 50, y: 14, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },

  // Clásica defensiva con 5 medios
  "4-5-1": {
    id: "4-5-1",
    label: "4-5-1",
    slots: [
      { id: "gk",  label: "POR", x: 50, y: 89, compatiblePositions: ["POR", "GK"] },
      { id: "lb",  label: "LI",  x: 14, y: 70, compatiblePositions: ["LI", "LB", "LWB"] },
      { id: "cb1", label: "DFC", x: 36, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "cb2", label: "DFC", x: 64, y: 74, compatiblePositions: ["DFC", "CB", "SW"] },
      { id: "rb",  label: "LD",  x: 86, y: 70, compatiblePositions: ["LD", "RB", "RWB"] },
      { id: "lm",  label: "MI",  x: 10, y: 47, compatiblePositions: ["MI", "LM", "EI", "LW"] },
      { id: "cm1", label: "MC",  x: 28, y: 49, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "cm2", label: "MC",  x: 50, y: 47, compatiblePositions: ["MC", "CM", "MCO", "CAM"] },
      { id: "cm3", label: "MC",  x: 72, y: 49, compatiblePositions: ["MC", "CM", "MCD", "CDM"] },
      { id: "rm",  label: "MD",  x: 90, y: 47, compatiblePositions: ["MD", "RM", "ED", "RW"] },
      { id: "st",  label: "DC",  x: 50, y: 14, compatiblePositions: ["DC", "ST", "CF", "SD", "SS"] },
    ],
  },
};

export const FORMATION_IDS: FormationId[] = [
  "4-3-3",
  "4-4-2",
  "4-2-3-1",
  "4-2-1-3",
  "4-4-1-1",
  "4-2-2-2",
  "4-3-2-1",
  "4-1-2-1-2",
  "3-5-2",
  "5-2-1-2",
  "3-4-3",
  "3-4-2-1",
  "4-1-4-1",
  "4-5-1",
];

export default formations;
