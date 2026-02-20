import { ReactNode } from "react";

interface StatCardProps {
  label: string;
  value: string;
  sub?: string;
  icon?: ReactNode;
  accent?: boolean;
  trend?: "up" | "down" | "neutral";
}

export default function StatCard({
  label,
  value,
  sub,
  icon,
  accent = false,
  trend,
}: StatCardProps) {
  return (
    <div
      className={`
        bg-[#131722] rounded-2xl p-5 border flex flex-col gap-4
        transition-all duration-200 hover:bg-[#1A1F2E]
        ${accent
          ? "border-[#8B5CF6]/20 shadow-lg shadow-[#8B5CF6]/5"
          : "border-white/[0.04]"
        }
      `}
    >
      <div className="flex items-center justify-between">
        <span className="text-[#9CA3AF] text-xs font-medium uppercase tracking-wider">
          {label}
        </span>
        {icon && (
          <span className="w-8 h-8 rounded-lg bg-[#8B5CF6]/10 flex items-center justify-center text-[#8B5CF6]">
            {icon}
          </span>
        )}
      </div>

      <div>
        <p className="text-[#F3F4F6] text-2xl font-semibold tracking-tight leading-none">
          {value}
        </p>
        {sub && (
          <p
            className={`text-xs mt-1.5 ${
              trend === "up"
                ? "text-[#22C55E]"
                : trend === "down"
                ? "text-[#EF4444]"
                : "text-[#9CA3AF]"
            }`}
          >
            {sub}
          </p>
        )}
      </div>
    </div>
  );
}
