//
//  ViewController.m
//  LFLiveKitDemo
//
//  Created by admin on 16/8/30.
//  Copyright © 2016年 admin. All rights reserved.
//

#import "ViewController.h"
#import "previewController.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextField *host;
@property (weak, nonatomic) IBOutlet UITextField *port;
@property (weak, nonatomic) IBOutlet UITextField *url;
@property (strong, nonatomic, nullable) previewController *previewVC;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

}
- (IBAction)didTouchOK:(id)sender {
    [self.view endEditing:YES];

    self.previewVC = [[previewController alloc]init];
    self.previewVC.host = self.host.text;
    self.previewVC.port = self.port.text;
    self.previewVC.url = self.url.text;
    __weak typeof (self) wSelf = self;
    self.previewVC.didClose = ^{
        [wSelf.previewVC dismissViewControllerAnimated:YES completion:^{
        }];
        wSelf.previewVC = nil;
    };
    
    [self presentViewController:self.previewVC animated:YES completion:^{
    }];
    
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES;
}

@end
