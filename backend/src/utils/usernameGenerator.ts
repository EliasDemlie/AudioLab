export function generateUsername(): string {
  return `user_${Math.random().toString(36).substring(2, 10)}`;
}