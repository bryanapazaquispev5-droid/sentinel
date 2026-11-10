import { z } from "zod";

const currentYear = new Date().getUTCFullYear();

export const profileSchema = z.object({
  name: z.string().trim().min(2).max(80).optional(),
  gender: z.enum(["FEMALE", "MALE", "NON_BINARY", "PREFER_NOT_TO_SAY"]).nullable().optional(),
  birthYear: z.number().int().min(1900).max(currentYear - 13).nullable().optional(),
  avatarBase64: z.string().max(2_000_000).nullable().optional()
}).refine((value) => Object.keys(value).length > 0, "Debes enviar al menos un dato para actualizar");

export const passwordSchema = z.object({
  currentPassword: z.string().min(1).max(100),
  newPassword: z.string().min(8).max(100)
});
