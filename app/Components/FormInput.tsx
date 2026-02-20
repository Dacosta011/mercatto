import { InputHTMLAttributes, ReactNode } from "react";

interface FormInputProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
  hint?: string;
  error?: string;
  icon?: ReactNode;
  suffix?: ReactNode;
}

export default function FormInput({
  label,
  hint,
  error,
  icon,
  suffix,
  className = "",
  id,
  ...props
}: FormInputProps) {
  const inputId = id ?? label.toLowerCase().replace(/\s+/g, "-");

  return (
    <div className="flex flex-col gap-1.5">
      <label
        htmlFor={inputId}
        className="text-[#F3F4F6] text-sm font-medium"
      >
        {label}
      </label>

      <div className="relative flex items-center">
        {icon && (
          <span className="absolute left-3.5 text-[#9CA3AF] pointer-events-none flex items-center">
            {icon}
          </span>
        )}
        <input
          id={inputId}
          className={`
            w-full bg-[#0D0F14] border rounded-xl py-3 text-sm text-[#F3F4F6]
            placeholder-[#9CA3AF]/40
            transition-all duration-200
            focus:outline-none focus:border-[#8B5CF6]/60 focus:ring-2 focus:ring-[#8B5CF6]/10
            disabled:opacity-40 disabled:cursor-not-allowed
            ${error ? "border-[#EF4444]/50 focus:border-[#EF4444]/70 focus:ring-[#EF4444]/10" : "border-white/[0.07] hover:border-white/12"}
            ${icon ? "pl-10" : "pl-4"}
            ${suffix ? "pr-12" : "pr-4"}
            ${className}
          `}
          {...props}
        />
        {suffix && (
          <span className="absolute right-3.5 text-[#9CA3AF] flex items-center">
            {suffix}
          </span>
        )}
      </div>

      {(hint || error) && (
        <p
          className={`text-xs ${error ? "text-[#EF4444]" : "text-[#9CA3AF]"}`}
        >
          {error ?? hint}
        </p>
      )}
    </div>
  );
}
