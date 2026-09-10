import * as random from "@pulumi/random";

// Credential-free demo resources — no cloud account required.
const pet = new random.RandomPet("pet", { length: 2 });

const password = new random.RandomPassword("password", {
    length: 16,
    special: true,
});

export const petName = pet.id;
export const password_ = password.result; // marked secret by the provider
