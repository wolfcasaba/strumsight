/// Public account contract for other features.
///
/// Feature consumers must import this boundary instead of auth internals.
library;

export 'providers/auth_providers.dart'
    show
        accountApiClientProvider,
        accountEnabledProvider,
        authControllerProvider,
        authEventProvider,
        AuthController,
        AuthEvent;
