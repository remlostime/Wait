import { generateKeyPairSync } from "node:crypto"

const pair = generateKeyPairSync("ec", {
  namedCurve: "prime256v1",
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
})

export const TEST_APNS_PRIVATE_KEY_PEM: string = pair.privateKey
export const TEST_APNS_PUBLIC_KEY_PEM: string = pair.publicKey
/** The shape APNS_KEY has in Vercel: base64 of the PEM. */
export const TEST_APNS_KEY_BASE64: string = Buffer.from(pair.privateKey).toString("base64")
