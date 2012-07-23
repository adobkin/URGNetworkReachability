URGNetworkReachability
======================

URGNetworkReachability is  simple class for monitoring Reachability of network for iOS. 
Class compatible with ARC and non-ARC

## A Simple example
      URGNetworkReachability *reach = [[URGNetworkReachability alloc] init];
	
      // set the block
      reach.reachabilityChangedBlock = ^(URGNetworkReachability *reach) {
          NSString *status = nil;
          if (reach.isReacheble) {
             if (reach.isReachebleViaWiFi) {
                status = @"network is reachable via WiFi";
             } else {
                status = @"network is reachable via Cellular";
             }
          } else {
             status = @"network is unreachable";
          }
          NSLog(@"%@", status);
      };
				
      [reach startNotifier];

## Use

    - Add URGNetworkReachability.h and URGNetworkReachability.m files to your project 
    - Add SystemConfiguration.framework to your project