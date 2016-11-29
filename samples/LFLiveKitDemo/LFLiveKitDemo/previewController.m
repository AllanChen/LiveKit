//
//  previewController.m
//  LFLiveKitDemo
//
//  Created by hyq on 16/10/18.
//  Copyright © 2016年 admin. All rights reserved.
//

#import "previewController.h"
#import "LFLivePreview.h"

@interface previewController ()
@property(strong, nonatomic, nullable) LFLivePreview *livePreview;
@end

@implementation previewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.livePreview) {
        self.livePreview = [[LFLivePreview alloc] initWithFrame:self.view.bounds];
        self.livePreview.host = self.host;
        self.livePreview.port = [self.port integerValue];
        self.livePreview.url = self.url;
        self.livePreview.didClose = self.didClose;
        self.livePreview.onLive = YES;
        [self.view addSubview:self.livePreview];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscapeRight;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES;
}

- (void)dealloc {
    self.livePreview.onLive = NO;
    [self.livePreview removeFromSuperview];
    self.livePreview = nil;
}

@end
