import Button from "./Button";

interface PlayerCardProps {
  name: string;
  position: string;
  club?: string;
  ovr: number;
  price: string;
  clause: string;
  action?: "buy" | "list";
  onAction?: () => void;
}

function OvrColor(ovr: number): string {
  if (ovr >= 88) return "#8B5CF6";
  if (ovr >= 82) return "#22C55E";
  if (ovr >= 75) return "#F59E0B";
  return "#9CA3AF";
}

export default function PlayerCard({
  name,
  position,
  club,
  ovr,
  price,
  clause,
  action = "buy",
  onAction,
}: PlayerCardProps) {
  const ovrColor = OvrColor(ovr);

  return (
    <div className="bg-[#131722] rounded-2xl p-5 border border-white/[0.04] hover:border-[#8B5CF6]/20 hover:bg-[#1A1F2E] transition-all duration-200 flex flex-col gap-4 group">
      {/* Header */}
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[#F3F4F6] font-semibold text-sm leading-tight truncate">
            {name}
          </p>
          <div className="flex items-center gap-1.5 mt-1">
            <span className="text-[#9CA3AF] text-xs">{position}</span>
            {club && (
              <>
                <span className="text-[#9CA3AF]/40 text-xs">·</span>
                <span className="text-[#9CA3AF] text-xs truncate">{club}</span>
              </>
            )}
          </div>
        </div>
        <div className="shrink-0 text-right">
          <span
            className="text-3xl font-black tracking-tighter leading-none"
            style={{ color: ovrColor }}
          >
            {ovr}
          </span>
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mt-0.5">
            OVR
          </p>
        </div>
      </div>

      {/* Divider */}
      <div className="h-px bg-white/[0.04]" />

      {/* Pricing */}
      <div className="space-y-2">
        <div className="flex justify-between items-center">
          <span className="text-[#9CA3AF] text-xs">Precio</span>
          <span className="text-[#F3F4F6] text-sm font-semibold">
            {price}
          </span>
        </div>
        <div className="flex justify-between items-center">
          <span className="text-[#9CA3AF] text-xs">Cláusula</span>
          <span className="text-[#EF4444] text-sm font-semibold">{clause}</span>
        </div>
      </div>

      {/* Action */}
      <Button
        variant={action === "buy" ? "primary" : "secondary"}
        size="sm"
        className="w-full"
        onClick={onAction}
      >
        {action === "buy" ? "Comprar" : "Listar"}
      </Button>
    </div>
  );
}
