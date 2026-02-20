import Sidebar from "../Components/Sidebar";
import RouteGuard from "../Components/RouteGuard";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex h-screen overflow-hidden bg-[#0D0F14]">
      <Sidebar />
      <RouteGuard>
        <main className="flex-1 overflow-y-auto">{children}</main>
      </RouteGuard>
    </div>
  );
}
