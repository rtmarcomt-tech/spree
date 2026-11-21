import { expect, test } from '@playwright/test'
import { invitationAcceptancePath, login, SELLER_PANEL, sendSellerInvitation } from './helpers'

/**
 * Creates a seller, invites someone, and accepts on the panel — returning the
 * signed-in seller page. The invitation flow has its own spec; this is the
 * precondition for anything a seller does afterwards.
 */
async function signInAsNewSeller(
  page: import('@playwright/test').Page,
  browser: import('@playwright/test').Browser,
) {
  const creds = await login(page)
  const suffix = Date.now()
  const sellerName = `E2E Packaging Seller ${suffix}`

  await page.goto(`/${creds.store_id}/sellers`)
  await page.getByRole('button', { name: /add seller/i }).click()
  await page.locator('#name').fill(sellerName)
  await page.getByRole('button', { name: /create seller/i }).click()
  await expect(page.getByRole('heading', { name: sellerName })).toBeVisible({ timeout: 15_000 })

  await page
    .getByRole('button', { name: /^invite$/i })
    .first()
    .click()
  await page.locator('#invite-email').fill(`e2e-packaging-${suffix}@example.com`)

  const invitationPath = await sendSellerInvitation(page)
  const acceptancePath = await invitationAcceptancePath(page, creds, invitationPath)

  const context = await browser.newContext()
  const sellerPage = await context.newPage()
  await sellerPage.goto(`${SELLER_PANEL}${acceptancePath}`)
  await expect(sellerPage.getByLabel(/^password$/i)).toBeVisible({ timeout: 20_000 })
  await sellerPage.getByLabel(/first name/i).fill('Pat')
  await sellerPage.getByLabel(/last name/i).fill('Carlson')
  await sellerPage.getByLabel(/^password$/i).fill('e2e-password-123')
  await sellerPage.getByLabel(/confirm password/i).fill('e2e-password-123')
  await sellerPage.getByRole('button', { name: /accept|create account|join/i }).click()
  await expect(sellerPage).not.toHaveURL(/accept-invitation/, { timeout: 20_000 })

  return { context, sellerPage, sellerName }
}

test.describe('seller packaging', () => {
  // Creating a seller, inviting, accepting, then walking two panel pages does
  // not fit the suite's default budget — the preamble alone is four round
  // trips before this spec's own subject starts.
  test.slow()

  test('a digital-only seller is not asked for physical shipping details', async ({
    page,
    browser,
  }) => {
    const { context, sellerPage } = await signInAsNewSeller(page, browser)

    try {
      const boxName = `E2E Mailer ${Date.now()}`

      // Navigated by clicking rather than by a built URL: acceptance lands on
      // the panel root and the seller id only appears in the path once the
      // panel has resolved which seller this user acts for. A hand-built path
      // races that and sends requests carrying no seller header.
      // "Setup" is what the panel calls the onboarding checklist in its nav
      // and its heading.
      const goToSetup = async () => {
        await sellerPage.getByRole('link', { name: /setup/i }).first().click()
        await expect(sellerPage.getByRole('heading', { name: /^setup$/i })).toBeVisible({
          timeout: 20_000,
        })
      }

      // Digital-only onboarding deliberately omits physical shipping requirements.
      await goToSetup()
      await expect(sellerPage.getByText(/shipping box/i)).toHaveCount(0)
      await expect(sellerPage.getByText(/package type/i)).toHaveCount(0)
    } finally {
      await context.close()
    }
  })
})
