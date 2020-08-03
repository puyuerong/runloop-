//
//  runloop源码分析.m
//  objc4-test
//
//  Created by 蒲悦蓉 on 2020/7/31.
//

#import <Foundation/Foundation.h>

//Runloop结构体
    struct __CFRunLoop {
        CFRuntimeBase _base;
        pthread_mutex_t _lock;            /* locked for accessing mode list *///访问mode集合时用到的锁 32行
        __CFPort _wakeUpPort;            // used for CFRunLoopWakeUp 手动唤醒runloop的  37行
        Boolean _unused;
        volatile _per_run_data *_perRunData;              // reset for runs of the run loop的端口。初始化runloop时设置，仅用于CFRunLoopWakeUp，CFRunLoopWakeUp函数会向_wakeUpPort发送一条消息
        pthread_t _pthread;      //对应的线程
        uint32_t _winthread;
        CFMutableSetRef _commonModes;      // 集合，存储的是字符串，记录所有标记为common的modeName 44行
        CFMutableSetRef _commonModeItems;    //存储所有commonMode的sources、timers、observers
        CFRunLoopModeRef _currentMode;        //当前modeName
        CFMutableSetRef _modes;                // 集合，存储的是CFRunLoopModeRef
        struct _block_item *_blocks_head;   // 链表头指针，该链表保存了所有需要被runloop执行的block。外部通过调用CFRunLoopPerformBlock函数来向链表中添加一个block节点。runloop会在CFRunLoopDoBlock时遍历该链表，逐一执行block
        struct _block_item *_blocks_tail;    // 链表尾指针，之所以有尾指针，是为了降低增加block时的时间复杂度
        };
        CFAbsoluteTime _runTime;
        CFAbsoluteTime _sleepTime;
        CFTypeRef _counterpart;
    };


    pthread_mutex_t
    typedef __darwin_pthread_mutex_t pthread_mutex_t
    typedef struct _opaque_pthread_mutex_t __darwin_pthread_mutex_t;
    struct _opaque_pthread_mutex_t

    __CFPort
    typedef mach_port_t __CFPort;
    typedef __darwin_mach_port_t mach_port_t;
    typedef __darwin_mach_port_name_t __darwin_mach_port_t;
    typedef __darwin_natural_t __darwin_mach_port_name_t;
    typedef unsigned int __darwin_natural_t;

    CFMutableSetRef
    typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableSet) __CFSet * CFMutableSetRef;


//Runloop的几种状态
    typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
        kCFRunLoopEntry = (1UL << 0),            //即将进入RunLoop
        kCFRunLoopBeforeTimers = (1UL << 1),     //即将处理timer
        kCFRunLoopBeforeSources = (1UL << 2),    //即将处理source
        kCFRunLoopBeforeWaiting = (1UL << 5),    //即将进入休眠
        kCFRunLoopAfterWaiting = (1UL << 6),     //被唤醒但是还没开始处理事件
        kCFRunLoopExit = (1UL << 7),             //RunLoop已经退出
        kCFRunLoopAllActivities = 0x0FFFFFFFU
    };

//获取runloop的主线程
    CFRunLoopRef CFRunLoopGetMain(void) {
        CHECK_FOR_FORK();
        static CFRunLoopRef __main = NULL; // no retain needed
        if (!__main) __main = _CFRunLoopGet0(pthread_main_thread_np()); // no CAS needed
        return __main;
    }

//获取当前线程
    CFRunLoopRef CFRunLoopGetCurrent(void) {
        CHECK_FOR_FORK();
        CFRunLoopRef rl = (CFRunLoopRef)_CFGetTSD(__CFTSDKeyRunLoop);
        if (rl) return rl;
        return _CFRunLoopGet0(pthread_self());
    }

//_CFRunLoopGet0()

    // 声明一个全局的可变字典 __CFRunLoops用于存储每一条线程和对应的runloop
    // __CFRunLoops的键key存储线程pthread_t，值存储runloop
    static CFMutableDictionaryRef __CFRunLoops = NULL;
    // loopsLock用于访问 __CFRunLoops时加锁，锁的目的是：考虑线程安全问题，防止多条线程同时访问 __CFRunLoop对应的内存空间
    static CFLock_t loopsLock = CFLockInit;

    // should only be called by Foundation
    // t==0 is a synonym for "main thread" that always works
    CF_EXPORT CFRunLoopRef _CFRunLoopGet0(pthread_t t) {
        // 判断t所指向的线程是否为空，如果为空，就获取当前主线程进行赋值
        if (pthread_equal(t, kNilPthreadT)) {
        t = pthread_main_thread_np();
        }
        // 处理线程安全，加锁
        __CFLock(&loopsLock);
        // 判断全局的可变字典 __CFRunLoops是否为空
        // 如果为空
        if (!__CFRunLoops) {
            // 解锁
            __CFUnlock(&loopsLock);
            // 定义一个局部可变字典dict
        CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
            // 创建一个与主线程对应的RunLoop对象mainLoop
        CFRunLoopRef mainLoop = __CFRunLoopCreate(pthread_main_thread_np());
            // 把主线程和主线程对应的mainLoop存储于字典dict
        CFDictionarySetValue(dict, pthreadPointer(pthread_main_thread_np()), mainLoop);
            // 把局部创建的字典dict赋值给全局字典__RunLoops
        if (!OSAtomicCompareAndSwapPtrBarrier(NULL, dict, (void * volatile *)&__CFRunLoops)) {
            // 赋值成功后，release局部变量
            CFRelease(dict);
        }
            // 存储mainLoop到字典以后，撤销一次引用，即release一次mainLoop，因为mainLoop存储到字典后会自动retain
        CFRelease(mainLoop);
            // 加锁
            __CFLock(&loopsLock);
        }
        // 从全局的字典 __CFRunLoops中获取对应于当前线程的RunLoop
        CFRunLoopRef loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
        // 解锁
        __CFUnlock(&loopsLock);
        // 如果获取不到RunLoop就创建并存储
        // 注意：在子线程中第一次获取RunLoop是获取不到的，获取不到的时候才去创建，这个if语句一般在子线程中第一次获取的时候才会执行
        if (!loop) {
            // 根据当前线程创建一个RunLoop
        CFRunLoopRef newLoop = __CFRunLoopCreate(t);
            // 加锁
            __CFLock(&loopsLock);
            // 再一次从全局的字典 __CFRunLoops中获取对应于当前线程的RunLoop
        loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
            // 如果还是获取不到RunLoop，就存储当前线程和刚创建的RunLoop到全局字典 __CFRunLoops
        if (!loop) {
            // 存储当前线程和刚创建的RunLoop到全局字典 __CFRunLoops
            CFDictionarySetValue(__CFRunLoops, pthreadPointer(t), newLoop);
            // 加锁
            loop = newLoop;
        }
            // don't release run loops inside the loopsLock, because CFRunLoopDeallocate may end up taking it
            // 解锁
            __CFUnlock(&loopsLock);
            // release局部的newLoop
        CFRelease(newLoop);
        }
        // 判断t是否为当前线程，如果是就注册一个回调，当线程销毁的时候，也销毁其对应的RunLoop
        if (pthread_equal(t, pthread_self())) {
            _CFSetTSD(__CFTSDKeyRunLoop, (void *)loop, NULL);
            if (0 == _CFGetTSD(__CFTSDKeyRunLoopCntr)) {
                // 注册一个回调，当线程销毁时，顺便也销毁其对应的 RunLoop
                _CFSetTSD(__CFTSDKeyRunLoopCntr, (void *)(PTHREAD_DESTRUCTOR_ITERATIONS-1), (void (*)(void *))__CFFinalizeRunLoop);
            }
        }
        // 返回当前线程对应的RunLoop
        return loop;
    }

//CFRunLoopRun
    // 供外部调用的公开的CFRunLoopRun方法，其内部会调用CFRunLoopRunSpecific
    void CFRunLoopRun(void) {    /* DOES CALLOUT */
        int32_t result;
        do {
            // 调用CFRunLoopRunSpecific
            result = CFRunLoopRunSpecific(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 1.0e10, false);
            CHECK_FOR_FORK();
        } while (kCFRunLoopRunStopped != result && kCFRunLoopRunFinished != result);
    }

//CFRunLoopRunSpecific
    // 其内部会调用 __CFRunLoopRun 函数
    SInt32 CFRunLoopRunSpecific(CFRunLoopRef rl, CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {     /* DOES CALLOUT */
        CHECK_FOR_FORK();
        if (__CFRunLoopIsDeallocating(rl)) return kCFRunLoopRunFinished;
        __CFRunLoopLock(rl);
        // 首先根据modeName找到对应mode
        CFRunLoopModeRef currentMode = __CFRunLoopFindMode(rl, modeName, false);
        // 如果没找到 || 如果mode里没有source/timer/observer, 直接返回
        if (NULL == currentMode || __CFRunLoopModeIsEmpty(rl, currentMode, rl->_currentMode)) {
        Boolean did = false;
        if (currentMode) __CFRunLoopModeUnlock(currentMode);
        __CFRunLoopUnlock(rl);
        return did ? kCFRunLoopRunHandledSource : kCFRunLoopRunFinished;
        }
        volatile _per_run_data *previousPerRun = __CFRunLoopPushPerRunData(rl);
        // 设置现在的previousMode和currentMode
        CFRunLoopModeRef previousMode = rl->_currentMode;
        rl->_currentMode = currentMode;
        // 初始化一个result为kCFRunLoopRunFinished
        int32_t result = kCFRunLoopRunFinished;
        // 通知observer：即将进入runloop
        if (currentMode->_observerMask & kCFRunLoopEntry ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopEntry);
        // 核心的Loop逻辑
        result = __CFRunLoopRun(rl, currentMode, seconds, returnAfterSourceHandled, previousMode);
        // 通知Observers：退出Loop
        if (currentMode->_observerMask & kCFRunLoopExit ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopExit);

            __CFRunLoopModeUnlock(currentMode);
            __CFRunLoopPopPerRunData(rl, previousPerRun);
        rl->_currentMode = previousMode;
        __CFRunLoopUnlock(rl);
        return result;
    }


//__CFRunLoopRun
    static int32_t __CFRunLoopRun(CFRunLoopRef rl, CFRunLoopModeRef rlm, CFTimeInterval seconds, Boolean stopAfterHandle, CFRunLoopModeRef previousMode) {
        //获取当前内核时间
        uint64_t startTSR = mach_absolute_time();

        //如果当前runLoop或者runLoopMode为停止状态的话直接返回
        if (__CFRunLoopIsStopped(rl)) {
            __CFRunLoopUnsetStopped(rl);
        return kCFRunLoopRunStopped;
        } else if (rlm->_stopped) {
        rlm->_stopped = false;
        return kCFRunLoopRunStopped;
        }
        
        //判断是否是第一次在主线程中启动RunLoop,如果是且当前RunLoop为主线程的RunLoop，那么就给分发一个队列调度端口
        mach_port_name_t dispatchPort = MACH_PORT_NULL;
        Boolean libdispatchQSafe = pthread_main_np() && ((HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && NULL == previousMode) || (!HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && 0 == _CFGetTSD(__CFTSDKeyIsInGCDMainQ)));
        if (libdispatchQSafe && (CFRunLoopGetMain() == rl) && CFSetContainsValue(rl->_commonModes, rlm->_name)) dispatchPort = _dispatch_get_main_queue_port_4CF();
        
    #if USE_DISPATCH_SOURCE_FOR_TIMERS
        //给当前模式分发队列端口
        mach_port_name_t modeQueuePort = MACH_PORT_NULL;
        if (rlm->_queue) {
            modeQueuePort = _dispatch_runloop_root_queue_get_port_4CF(rlm->_queue);
            if (!modeQueuePort) {
                CRASH("Unable to get port for run loop mode queue (%d)", -1);
            }
        }
    #endif
        //初始化一个GCD计时器，用于管理当前模式的超时
        dispatch_source_t timeout_timer = NULL;
        struct __timeout_context *timeout_context = (struct __timeout_context *)malloc(sizeof(*timeout_context));
        if (seconds <= 0.0) { // instant timeout
            seconds = 0.0;
            timeout_context->termTSR = 0ULL;
        } else if (seconds <= TIMER_INTERVAL_LIMIT) {
            dispatch_queue_t queue = pthread_main_np() ? __CFDispatchQueueGetGenericMatchingMain() : __CFDispatchQueueGetGenericBackground();
            timeout_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
                dispatch_retain(timeout_timer);
            timeout_context->ds = timeout_timer;
            timeout_context->rl = (CFRunLoopRef)CFRetain(rl);
            timeout_context->termTSR = startTSR + __CFTimeIntervalToTSR(seconds);
            dispatch_set_context(timeout_timer, timeout_context); // source gets ownership of context
            dispatch_source_set_event_handler_f(timeout_timer, __CFRunLoopTimeout);
            dispatch_source_set_cancel_handler_f(timeout_timer, __CFRunLoopTimeoutCancel);
            uint64_t ns_at = (uint64_t)((__CFTSRToTimeInterval(startTSR) + seconds) * 1000000000ULL);
            dispatch_source_set_timer(timeout_timer, dispatch_time(1, ns_at), DISPATCH_TIME_FOREVER, 1000ULL);
            dispatch_resume(timeout_timer);
        } else { // infinite timeout
            seconds = 9999999999.0;
            timeout_context->termTSR = UINT64_MAX;
        }

        // 第一步，进入循环
        Boolean didDispatchPortLastTime = true;
        int32_t retVal = 0;
        do {
    #if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
            voucher_mach_msg_state_t voucherState = VOUCHER_MACH_MSG_STATE_UNCHANGED;
            voucher_t voucherCopy = NULL;
    #endif
            uint8_t msg_buffer[3 * 1024];
    #if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
            mach_msg_header_t *msg = NULL;
            mach_port_t livePort = MACH_PORT_NULL;
    #elif DEPLOYMENT_TARGET_WINDOWS
            HANDLE livePort = NULL;
            Boolean windowsMessageReceived = false;
    #endif
            __CFPortSet waitSet = rlm->_portSet;

            //设置当前循环监听端口的唤醒
            __CFRunLoopUnsetIgnoreWakeUps(rl);

            // 第二步，通知观察者准备开始处理Timer源事件
            if (rlm->_observerMask & kCFRunLoopBeforeTimers) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeTimers);
            // 第三步，通知观察者准备开始处理Source源事件
            if (rlm->_observerMask & kCFRunLoopBeforeSources) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeSources);

            //执行提交到runLoop中的block
            __CFRunLoopDoBlocks(rl, rlm);

            // 第四步，执行source0中的源事件
            Boolean sourceHandledThisLoop = __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
            //如果当前source0源事件处理完成后执行提交到runLoop中的block
            if (sourceHandledThisLoop) {
                __CFRunLoopDoBlocks(rl, rlm);
            }

            //标志是否等待端口唤醒
            Boolean poll = sourceHandledThisLoop || (0ULL == timeout_context->termTSR);

            //第五步，检测端口，如果端口有事件则跳转至handle_msg（首次执行不会进入判断，因为didDispatchPortLastTime为true）
            if (MACH_PORT_NULL != dispatchPort && !didDispatchPortLastTime) {
    #if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
                msg = (mach_msg_header_t *)msg_buffer;
                if (__CFRunLoopServiceMachPort(dispatchPort, &msg, sizeof(msg_buffer), &livePort, 0, &voucherState, NULL)) {
                    goto handle_msg;
                }
    #elif DEPLOYMENT_TARGET_WINDOWS
                if (__CFRunLoopWaitForMultipleObjects(NULL, &dispatchPort, 0, 0, &livePort, NULL)) {
                    goto handle_msg;
                }
    #endif
            }

            didDispatchPortLastTime = false;

            // 第六步，通知观察者线程进入休眠
            if (!poll && (rlm->_observerMask & kCFRunLoopBeforeWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeWaiting);
            // 标志当前runLoop为休眠状态
            __CFRunLoopSetSleeping(rl);
            // do not do any user callouts after this point (after notifying of sleeping)

            // Must push the local-to-this-activation ports in on every loop
            // iteration, as this mode could be run re-entrantly and we don't
            // want these ports to get serviced.

            __CFPortSetInsert(dispatchPort, waitSet);
                
            __CFRunLoopModeUnlock(rlm);
            __CFRunLoopUnlock(rl);

            CFAbsoluteTime sleepStart = poll ? 0.0 : CFAbsoluteTimeGetCurrent();

    #if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
    #if USE_DISPATCH_SOURCE_FOR_TIMERS
            // 第七步，进入循环开始不断的读取端口信息，如果端口有唤醒信息则唤醒当前runLoop
            do {
                if (kCFUseCollectableAllocator) {
                    // objc_clear_stack(0);
                    // <rdar://problem/16393959>
                    memset(msg_buffer, 0, sizeof(msg_buffer));
                }
                msg = (mach_msg_header_t *)msg_buffer;
                
                __CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy);
                
                if (modeQueuePort != MACH_PORT_NULL && livePort == modeQueuePort) {
                    // Drain the internal queue. If one of the callout blocks sets the timerFired flag, break out and service the timer.
                    while (_dispatch_runloop_root_queue_perform_4CF(rlm->_queue));
                    if (rlm->_timerFired) {
                        // Leave livePort as the queue port, and service timers below
                        rlm->_timerFired = false;
                        break;
                    } else {
                        if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);
                    }
                } else {
                    // Go ahead and leave the inner loop.
                    break;
                }
            } while (1);
    #else
            if (kCFUseCollectableAllocator) {
                // objc_clear_stack(0);
                // <rdar://problem/16393959>
                memset(msg_buffer, 0, sizeof(msg_buffer));
            }
            msg = (mach_msg_header_t *)msg_buffer;
            __CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy);
    #endif
            
            
    #elif DEPLOYMENT_TARGET_WINDOWS
            // Here, use the app-supplied message queue mask. They will set this if they are interested in having this run loop receive windows messages.
            __CFRunLoopWaitForMultipleObjects(waitSet, NULL, poll ? 0 : TIMEOUT_INFINITY, rlm->_msgQMask, &livePort, &windowsMessageReceived);
    #endif
            
            __CFRunLoopLock(rl);
            __CFRunLoopModeLock(rlm);

            rl->_sleepTime += (poll ? 0.0 : (CFAbsoluteTimeGetCurrent() - sleepStart));

            // Must remove the local-to-this-activation ports in on every loop
            // iteration, as this mode could be run re-entrantly and we don't
            // want these ports to get serviced. Also, we don't want them left
            // in there if this function returns.

            __CFPortSetRemove(dispatchPort, waitSet);
            
            //标志当前runLoop为唤醒状态
            __CFRunLoopSetIgnoreWakeUps(rl);

            // user callouts now OK again
            __CFRunLoopUnsetSleeping(rl);
            // 第八步，通知观察者线程被唤醒了
            if (!poll && (rlm->_observerMask & kCFRunLoopAfterWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopAfterWaiting);

            //执行端口的事件
            handle_msg:;
            //设置此时runLoop忽略端口唤醒（保证线程安全）（因为已经被唤醒了 在运行）
            __CFRunLoopSetIgnoreWakeUps(rl);

    #if DEPLOYMENT_TARGET_WINDOWS
            if (windowsMessageReceived) {
                // These Win32 APIs cause a callout, so make sure we're unlocked first and relocked after
                __CFRunLoopModeUnlock(rlm);
                __CFRunLoopUnlock(rl);

                if (rlm->_msgPump) {
                    rlm->_msgPump();
                } else {
                    MSG msg;
                    if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE | PM_NOYIELD)) {
                        TranslateMessage(&msg);
                        DispatchMessage(&msg);
                    }
                }
                
                __CFRunLoopLock(rl);
                __CFRunLoopModeLock(rlm);
                sourceHandledThisLoop = true;
                
                // To prevent starvation of sources other than the message queue, we check again to see if any other sources need to be serviced
                // Use 0 for the mask so windows messages are ignored this time. Also use 0 for the timeout, because we're just checking to see if the things are signalled right now -- we will wait on them again later.
                // NOTE: Ignore the dispatch source (it's not in the wait set anymore) and also don't run the observers here since we are polling.
                __CFRunLoopSetSleeping(rl);
                __CFRunLoopModeUnlock(rlm);
                __CFRunLoopUnlock(rl);
                
                __CFRunLoopWaitForMultipleObjects(waitSet, NULL, 0, 0, &livePort, NULL);
                
                __CFRunLoopLock(rl);
                __CFRunLoopModeLock(rlm);
                __CFRunLoopUnsetSleeping(rl);
                // If we have a new live port then it will be handled below as normal
            }
            
            
    #endif
            // 第九步，处理端口事件
            if (MACH_PORT_NULL == livePort) {
                CFRUNLOOP_WAKEUP_FOR_NOTHING();
                // handle nothing
            } else if (livePort == rl->_wakeUpPort) {
                CFRUNLOOP_WAKEUP_FOR_WAKEUP();
                // do nothing on Mac OS
    #if DEPLOYMENT_TARGET_WINDOWS
                // Always reset the wake up port, or risk spinning forever
                ResetEvent(rl->_wakeUpPort);
    #endif
            }
    #if USE_DISPATCH_SOURCE_FOR_TIMERS
            else if (modeQueuePort != MACH_PORT_NULL && livePort == modeQueuePort) {
                CFRUNLOOP_WAKEUP_FOR_TIMER();
                if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                    // Re-arm the next timer, because we apparently fired early
                    __CFArmNextTimerInMode(rlm, rl);
                }
            }
    #endif
    #if USE_MK_TIMER_TOO
            else if (rlm->_timerPort != MACH_PORT_NULL && livePort == rlm->_timerPort) {
                CFRUNLOOP_WAKEUP_FOR_TIMER();
                // On Windows, we have observed an issue where the timer port is set before the time which we requested it to be set. For example, we set the fire time to be TSR 167646765860, but it is actually observed firing at TSR 167646764145, which is 1715 ticks early. The result is that, when __CFRunLoopDoTimers checks to see if any of the run loop timers should be firing, it appears to be 'too early' for the next timer, and no timers are handled.
                // In this case, the timer port has been automatically reset (since it was returned from MsgWaitForMultipleObjectsEx), and if we do not re-arm it, then no timers will ever be serviced again unless something adjusts the timer list (e.g. adding or removing timers). The fix for the issue is to reset the timer here if CFRunLoopDoTimers did not handle a timer itself. 9308754
                if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                    // Re-arm the next timer
                    __CFArmNextTimerInMode(rlm, rl);
                }
            }
    #endif
            //处理有GCD提交到主线程唤醒的事件
            else if (livePort == dispatchPort) {
                CFRUNLOOP_WAKEUP_FOR_DISPATCH();
                __CFRunLoopModeUnlock(rlm);
                __CFRunLoopUnlock(rl);
                _CFSetTSD(__CFTSDKeyIsInGCDMainQ, (void *)6, NULL);
    #if DEPLOYMENT_TARGET_WINDOWS
                void *msg = 0;
    #endif
                __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__(msg);
                _CFSetTSD(__CFTSDKeyIsInGCDMainQ, (void *)0, NULL);
                __CFRunLoopLock(rl);
                __CFRunLoopModeLock(rlm);
                sourceHandledThisLoop = true;
                didDispatchPortLastTime = true;
            } else {
                
                //处理source1唤醒的事件
                CFRUNLOOP_WAKEUP_FOR_SOURCE();
                
                // If we received a voucher from this mach_msg, then put a copy of the new voucher into TSD. CFMachPortBoost will look in the TSD for the voucher. By using the value in the TSD we tie the CFMachPortBoost to this received mach_msg explicitly without a chance for anything in between the two pieces of code to set the voucher again.
                voucher_t previousVoucher = _CFSetTSD(__CFTSDKeyMachMessageHasVoucher, (void *)voucherCopy, os_release);

                // Despite the name, this works for windows handles as well
                CFRunLoopSourceRef rls = __CFRunLoopModeFindSourceForMachPort(rl, rlm, livePort);
                if (rls) {
    #if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
                    mach_msg_header_t *reply = NULL;
                            // 处理Source1(基于端口的源)
                    sourceHandledThisLoop = __CFRunLoopDoSource1(rl, rlm, rls, msg, msg->msgh_size, &reply) || sourceHandledThisLoop;
                    if (NULL != reply) {
                        (void)mach_msg(reply, MACH_SEND_MSG, reply->msgh_size, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
                        CFAllocatorDeallocate(kCFAllocatorSystemDefault, reply);
                    }
    #elif DEPLOYMENT_TARGET_WINDOWS
                    sourceHandledThisLoop = __CFRunLoopDoSource1(rl, rlm, rls) || sourceHandledThisLoop;
    #endif
                }
                
                // Restore the previous voucher
                _CFSetTSD(__CFTSDKeyMachMessageHasVoucher, previousVoucher, os_release);
                
            }
    #if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
            if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);
    #endif
            
            __CFRunLoopDoBlocks(rl, rlm);
            

            //返回对应的返回值并跳出循环
            if (sourceHandledThisLoop && stopAfterHandle) {
                retVal = kCFRunLoopRunHandledSource;
            } else if (timeout_context->termTSR < mach_absolute_time()) {
                retVal = kCFRunLoopRunTimedOut;
            } else if (__CFRunLoopIsStopped(rl)) {
                __CFRunLoopUnsetStopped(rl);
                retVal = kCFRunLoopRunStopped;
            } else if (rlm->_stopped) {
                rlm->_stopped = false;
                retVal = kCFRunLoopRunStopped;
            } else if (__CFRunLoopModeIsEmpty(rl, rlm, previousMode)) {
                retVal = kCFRunLoopRunFinished;
            }
            
    #if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
            voucher_mach_msg_revert(voucherState);
            os_release(voucherCopy);
    #endif

        } while (0 == retVal);

        // 第十步，释放定时器
        if (timeout_timer) {
            dispatch_source_cancel(timeout_timer);
            dispatch_release(timeout_timer);
        } else {
            free(timeout_context);
        }

        return retVal;
    }
