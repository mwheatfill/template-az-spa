import type { QueryClient } from "@tanstack/react-query";
import { createRootRouteWithContext, Link, Outlet } from "@tanstack/react-router";
import { useTheme } from "@/components/theme-provider";
import { Button } from "@/components/ui/button";

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  component: RootLayout,
  notFoundComponent: () => (
    <div className="flex min-h-screen items-center justify-center">
      <p className="text-muted-foreground">Not found.</p>
    </div>
  ),
});

function RootLayout() {
  const { theme, setTheme } = useTheme();
  return (
    <div className="min-h-screen bg-background text-foreground">
      <header className="border-b">
        <div className="mx-auto flex h-14 max-w-5xl items-center justify-between px-6">
          <nav className="flex items-center gap-4 text-sm">
            <Link to="/" className="font-semibold">
              Tier 1 SPA
            </Link>
            <Link to="/health" className="text-muted-foreground hover:text-foreground">
              Health
            </Link>
          </nav>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
          >
            Toggle theme
          </Button>
        </div>
      </header>
      <main className="mx-auto max-w-5xl px-6 py-10">
        <Outlet />
      </main>
    </div>
  );
}
