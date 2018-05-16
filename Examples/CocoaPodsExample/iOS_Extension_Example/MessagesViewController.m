//
//  MessagesViewController.m
//  iOS_Extension_Example
//
//  Created by Brandon Stalnaker on 1/8/18.
//  Copyright © 2018 mParticle, Inc. All rights reserved.
//

#import "MessagesViewController.h"
#import "mParticle.h"

@interface MessagesViewController ()
@property (weak, nonatomic) IBOutlet UIButton *button1;

@end

@implementation MessagesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"Your_App_Key" secret:@"Your_App_Secret"];
    
    // Sessions work within Extensions but are often superfluous with their short lifespan.
    options.automaticSessionTracking = FALSE;
    
    // See "Sharing Data with Your Containing App" here https://developer.apple.com/library/content/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html
    options.sharedGroupID = @"Set this to share user data between app and extension";
    
    [MParticle.sharedInstance startWithOptions:options];

    [MParticle sharedInstance].logLevel = MPILogLevelVerbose;
}
- (IBAction)pressButton1:(id)sender {
    MPEvent *event = [[MPEvent alloc] initWithName:@"extension button 1" type:MPEventTypeOther];
    
    [MParticle.sharedInstance logEvent:event];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Conversation Handling

-(void)didBecomeActiveWithConversation:(MSConversation *)conversation {
    // Called when the extension is about to move from the inactive to active state.
    // This will happen when the extension is about to present UI.
    
    // Use this method to configure the extension and restore previously stored state.
}

-(void)willResignActiveWithConversation:(MSConversation *)conversation {
    // Called when the extension is about to move from the active to inactive state.
    // This will happen when the user dissmises the extension, changes to a different
    // conversation or quits Messages.
    
    // Use this method to release shared resources, save user data, invalidate timers,
    // and store enough state information to restore your extension to its current state
    // in case it is terminated later.
}

-(void)didReceiveMessage:(MSMessage *)message conversation:(MSConversation *)conversation {
    // Called when a message arrives that was generated by another instance of this
    // extension on a remote device.
    
    // Use this method to trigger UI updates in response to the message.
}

-(void)didStartSendingMessage:(MSMessage *)message conversation:(MSConversation *)conversation {
    // Called when the user taps the send button.
}

-(void)didCancelSendingMessage:(MSMessage *)message conversation:(MSConversation *)conversation {
    // Called when the user deletes the message without sending it.
    
    // Use this to clean up state related to the deleted message.
}

-(void)willTransitionToPresentationStyle:(MSMessagesAppPresentationStyle)presentationStyle {
    // Called before the extension transitions to a new presentation style.
    
    // Use this method to prepare for the change in presentation style.
}

-(void)didTransitionToPresentationStyle:(MSMessagesAppPresentationStyle)presentationStyle {
    // Called after the extension transitions to a new presentation style.
    
    // Use this method to finalize any behaviors associated with the change in presentation style.
}

@end
