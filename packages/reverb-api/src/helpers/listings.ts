import type { ExecuteOptions } from "../executor.js";
import { CONDITIONS } from "../search.js";
import type { Helper, HelperCommand } from "./index.js";

/** Port of `reverb-api-cli/src/helpers/listings.rs`. */
export class ListingsHelper implements Helper {
  injectCommands(): readonly HelperCommand[] {
    return [
      {
        name: "+draft",
        about: "Create a listing in draft state with guided prompts",
        args: [
          {
            name: "make",
            help: "Instrument make (e.g. Fender)",
            required: true,
          },
          {
            name: "model",
            help: "Instrument model (e.g. Stratocaster)",
            required: true,
          },
          {
            name: "price",
            help: "Listing price in USD (e.g. 999.00)",
            required: true,
          },
          {
            name: "condition",
            help: "Item condition",
            required: true,
            choices: CONDITIONS,
          },
        ],
      },
    ];
  }

  async handle(options: ExecuteOptions): Promise<boolean> {
    if (options.method === "+draft") {
      await handleDraft(options);
      return true;
    }
    return false;
  }
}

async function handleDraft(options: ExecuteOptions): Promise<void> {
  const p = (options.params ?? {}) as Record<string, unknown>;
  // TODO (carried over from Rust): map condition name → Reverb condition UUID,
  // then POST to /listings. Skeleton placeholder, same as the Rust original.
  console.warn(
    `Creating draft listing: ${p.make} ${p.model} @ $${p.price} (${p.condition})`,
  );
  console.warn("(Not yet implemented — this is a skeleton placeholder)");
}
