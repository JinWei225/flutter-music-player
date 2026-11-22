import { runControl } from "./controls";

export default async function Command() {
  await runControl("shuffle");
}
