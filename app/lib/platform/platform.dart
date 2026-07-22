/// Platform layer: the two Android platform channels.
///
/// `network_binder/` (MethodChannel → ConnectivityManager.bindProcessToNetwork)
/// and `cook_service/` (foreground service host). See design 08 §8.3, §8.8.
/// Lands in M3–M4.
library;
