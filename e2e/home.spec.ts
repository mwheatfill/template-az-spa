import { expect, test } from "@playwright/test";

test("home page renders the design-token sample card", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Welcome" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Primary" })).toBeVisible();
});
