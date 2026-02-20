type BadgeStatus = "active" | "pending" | "complete" | "draft" | "assigned";

interface BadgeProps {
  status: BadgeStatus;
  label?: string;
}

const configs: Record<
  BadgeStatus,
  { dot: string; text: string; bg: string; label: string }
> = {
  active: {
    dot: "bg-[#22C55E]",
    text: "text-[#22C55E]",
    bg: "bg-[#22C55E]/10",
    label: "Activo",
  },
  pending: {
    dot: "bg-yellow-400",
    text: "text-yellow-400",
    bg: "bg-yellow-400/10",
    label: "Pendiente",
  },
  complete: {
    dot: "bg-[#8B5CF6]",
    text: "text-[#8B5CF6]",
    bg: "bg-[#8B5CF6]/10",
    label: "Completado",
  },
  draft: {
    dot: "bg-[#9CA3AF]",
    text: "text-[#9CA3AF]",
    bg: "bg-[#9CA3AF]/10",
    label: "Borrador",
  },
  assigned: {
    dot: "bg-[#22C55E]",
    text: "text-[#22C55E]",
    bg: "bg-[#22C55E]/10",
    label: "Asignado",
  },
};

export default function Badge({ status, label }: BadgeProps) {
  const cfg = configs[status];
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${cfg.bg} ${cfg.text}`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${cfg.dot} animate-pulse`} />
      {label ?? cfg.label}
    </span>
  );
}
