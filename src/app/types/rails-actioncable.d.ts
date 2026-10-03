// The part of @rails/actioncable (which ships no types) that src/app/lib/realtime.ts uses.
declare module '@rails/actioncable' {
  export interface SubscriptionCallbacks {
    connected?(): void;
    disconnected?(details: { willAttemptReconnect: boolean }): void;
    rejected?(): void;
    received?(data: unknown): void;
  }
  export interface Subscription {
    unsubscribe(): void;
  }
  export interface Consumer {
    subscriptions: { create(params: Record<string, unknown>, callbacks: SubscriptionCallbacks): Subscription };
    subprotocols: string[];
    connect(): void;
    disconnect(): void;
  }
  export function createConsumer(url: string | (() => string)): Consumer;
}
