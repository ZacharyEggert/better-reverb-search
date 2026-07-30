/**
 * Port of `reverb-api/src/schema.rs` — the API schema registry types.
 *
 * In the Rust crate these types are defined but never constructed; `executor.rs`
 * carries a `// TODO: load from schema registry` and hardcodes its method map.
 * The types are ported as-is; `methodsFor` below mirrors `schema_cmd::methods_for`,
 * which is the map the CLI actually uses today.
 */

export type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
export type ParameterLocation = "path" | "query";
export type ParamType = "string" | "integer" | "boolean" | "number";

export interface Parameter {
  description?: string;
  location: ParameterLocation;
  paramType: ParamType;
  required: boolean;
}

export interface RequestBody {
  description?: string;
  schema: unknown;
}

export interface ResponseSchema {
  schema: unknown;
}

/** A single API method on a resource (e.g. "list", "get", "create"). */
export interface Method {
  httpMethod: HttpMethod;
  /** Path relative to base_url. May contain `{id}` style placeholders. */
  path: string;
  description?: string;
  parameters: Record<string, Parameter>;
  requestBody?: RequestBody;
  response?: ResponseSchema;
  /** Field name in the response that holds the paginated collection. */
  pageKey?: string;
  /** Query parameter name used to pass the next-page cursor. */
  cursorParam?: string;
}

/** A top-level API resource (e.g. "listings", "orders"). */
export interface Resource {
  description?: string;
  methods: Record<string, Method>;
}

/** Top-level registry of all known Reverb API resources. */
export interface ApiSchema {
  baseUrl: string;
  resources: Record<string, Resource>;
}

/**
 * Port of `schema_cmd::methods_for`. Returns the method names for a resource.
 * TODO (carried over from Rust): load from a machine-readable schema registry.
 */
export function methodsFor(resource: string): string[] {
  switch (resource) {
    case "listings":
      return ["list", "get", "create", "update", "delete"];
    // case "orders": return ["list", "get"];
    // case "conversations": return ["list", "get", "create"];
    // case "shop": return ["get", "update"];
    // case "categories": return ["list"];
    // case "handpicked": return ["list", "get"];
    // case "priceguide": return ["get"];
    // case "shipping": return ["list", "create", "update", "delete"];
    // case "feedback": return ["list"];
    // case "webhooks": return ["list", "create", "delete"];
    default:
      return ["list", "get"];
  }
}
