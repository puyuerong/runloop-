//
//  TestViewController.m
//  RunloopTest
//
//  Created by 蒲悦蓉 on 2020/8/2.
//  Copyright © 2020 蒲悦蓉. All rights reserved.
//

#import "TestViewController.h"
#import "MyThread.h"

@interface TestViewController ()
@property (nonatomic, strong) MyThread * thread;
@property (nonatomic, assign)BOOL isstop;
@end

@implementation TestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
    
    UIButton * button  = [[UIButton alloc ] initWithFrame:CGRectMake(100, 10, 100, 100)];
    [self.view addSubview:button];
  //  [button addTarget:self action:@selector(add) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton * button1 = [[UIButton alloc ] initWithFrame:CGRectMake(200, 10, 100, 100)];
      [self.view addSubview:button1];
    button1.backgroundColor = [UIColor redColor];
    [button1 addTarget:self action:@selector(cancle) forControlEvents:UIControlEventTouchUpInside];
    
    self.view.backgroundColor = [UIColor orangeColor];
    self.isstop = NO;
 __weak   typeof(self) weakself = self;
    
    //self.thread = [[MyThread alloc] initWithTarget:weakself selector:@selector(start) object:nil];
    self.thread = [[MyThread alloc] initWithBlock:^{
//        [[NSRunLoop currentRunLoop] addPort: [[NSPort alloc]init] forMode:NSDefaultRunLoopMode];
//          [[NSRunLoop currentRunLoop] run];
        [weakself start];
//        while (!weakself.isstop && weakself) {
//          [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
//        }
        }];

    [self.thread start];
}


-(void) cancle {
   //[self __stop];
    [self.thread cancel];
    
    [self performSelector:@selector(__stop) onThread:self.thread withObject:nil waitUntilDone:YES];
    
}


-(void )__stop {
//    self.isstop =  YES;
//    CFRunLoopStop(CFRunLoopGetCurrent());
 //   [self.thread cancel];
    //self.thread = nil;
    
   // [MyThread exit];
   // [self dismissViewControllerAnimated:NO completion:nil];
    
}
-(void) start {
    [[NSRunLoop currentRunLoop] addPort: [[NSPort alloc]init] forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] run];
    }
//__weak   typeof(self) weakself = self;
//    [[NSRunLoop currentRunLoop] addPort: [[NSPort alloc]init] forMode:NSDefaultRunLoopMode];
//              [[NSRunLoop currentRunLoop] run];
//            while (!weakself.isstop && weakself) {
//              [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
//            }


- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [self dismissViewControllerAnimated:NO completion:nil];
}
- (void)dealloc
{
    [self cancle];
    
    
    NSLog(@"%s",__func__);
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
