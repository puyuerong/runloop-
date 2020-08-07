//
//  ViewController.m
//  RunloopTest
//
//  Created by 蒲悦蓉 on 2020/8/2.
//  Copyright © 2020 蒲悦蓉. All rights reserved.
//

#import "ViewController.h"
#import "TestViewController.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
   
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    TestViewController* viewController = [[TestViewController alloc] init];
//    viewController.view.backgroundColor = [UIColor orangeColor];
    viewController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:viewController animated:NO completion:nil];
}
@end
    
