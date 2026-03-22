import Sidebar from "../Components/Sidebar";
import BottomNav from "../Components/BottomNav";
import TopBar from "../Components/TopBar";
import RouteGuard from "../Components/RouteGuard";
import PhaseRedirectGuard from "../Components/PhaseRedirectGuard";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex h-dvh overflow-hidden bg-[#0D0F14]">
      {/* Desktop sidebar — hidden on mobile */}
      <div className="hidden lg:block">
        <Sidebar />
      </div>

      <PhaseRedirectGuard />

      <RouteGuard>
        <div className="flex-1 flex flex-col min-h-0 overflow-hidden">
          {/* Mobile top bar — hidden on desktop */}
          <TopBar />

          {/* Main content area */}
          <main className="flex-1 overflow-y-auto pb-28 lg:pb-0">
            {children}
          </main>

          {/* Mobile bottom nav — hidden on desktop */}
          <BottomNav />
        </div>
      </RouteGuard>
    </div>
  );
}
