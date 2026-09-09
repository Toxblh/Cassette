#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

#include "ios-auth.h"

static NSString *const AUTH_REDIRECT_HOST = @"music.yandex.";

typedef struct {
  char                 *token;
  CassetteTokenCallback callback;
  gpointer              userdata;
  GDestroyNotify        userdata_free;
} IdleData;

static gboolean
idle_fire (gpointer data)
{
  IdleData *d = data;
  d->callback (d->token, d->userdata);
  if (d->userdata_free && d->userdata)
    d->userdata_free (d->userdata);
  g_free (d->token);
  g_free (d);
  return G_SOURCE_REMOVE;
}

@interface CassetteAuthController : UIViewController <WKNavigationDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, assign) CassetteTokenCallback callback;
@property (nonatomic, assign) gpointer userdata;
@property (nonatomic, assign) GDestroyNotify userdata_free;
@property (nonatomic, assign) BOOL fired;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, copy) NSString *startUrl;
@end

static CassetteAuthController *g_current = nil;

@implementation CassetteAuthController

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor systemBackgroundColor];

  UIToolbar *bar = [[UIToolbar alloc] init];
  bar.translatesAutoresizingMaskIntoConstraints = NO;
  UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                          target:self
                                                                          action:@selector(cancel)];
  UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                         target:nil
                                                                         action:nil];
  UIBarButtonItem *title = [[UIBarButtonItem alloc] initWithTitle:@"Yandex" style:UIBarButtonItemStylePlain target:nil action:nil];
  title.enabled = NO;
  bar.items = @[ cancel, space, title, space ];
  [self.view addSubview:bar];

  WKWebViewConfiguration *config = [WKWebViewConfiguration new];
  self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
  self.webView.translatesAutoresizingMaskIntoConstraints = NO;
  self.webView.navigationDelegate = self;
  [self.view addSubview:self.webView];

  UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [bar.topAnchor constraintEqualToAnchor:safe.topAnchor],
    [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.webView.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
    [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
  ]];

  [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.startUrl]]];
}

- (void)finish:(NSString *)token
{
  if (self.fired)
    return;
  self.fired = YES;
  IdleData *d = g_new0 (IdleData, 1);
  d->token = token != nil ? g_strdup (token.UTF8String) : NULL;
  d->callback = self.callback;
  d->userdata = self.userdata;
  d->userdata_free = self.userdata_free;
  g_idle_add (idle_fire, d);
  g_current = nil;
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel
{
  [self finish:nil];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)controller
{
  [self finish:nil];
}

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))handler
{
  NSURL *url = action.request.URL;
  if ([url.absoluteString containsString:AUTH_REDIRECT_HOST] && url.fragment.length > 0)
    {
      NSURLComponents *components = [NSURLComponents new];
      components.query = url.fragment;
      for (NSURLQueryItem *item in components.queryItems)
        {
          if ([item.name isEqualToString:@"access_token"] && item.value.length > 0)
            {
              handler (WKNavigationActionPolicyCancel);
              [self finish:item.value];
              return;
            }
        }
    }
  handler (WKNavigationActionPolicyAllow);
}

@end

void
cassette_ios_auth_start (const char           *auth_url,
                         CassetteTokenCallback callback,
                         gpointer              userdata,
                         GDestroyNotify        userdata_free)
{
  NSString *url = [NSString stringWithUTF8String:auth_url];
  dispatch_async (dispatch_get_main_queue (), ^{
    if (g_current != nil)
      {
        if (userdata_free && userdata)
          userdata_free (userdata);
        return;
      }
    CassetteAuthController *controller = [[CassetteAuthController alloc] init];
    controller.callback = callback;
    controller.userdata = userdata;
    controller.userdata_free = userdata_free;
    controller.startUrl = url;
    controller.modalPresentationStyle = UIModalPresentationPageSheet;
    controller.presentationController.delegate = controller;
    g_current = controller;

    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
      {
        if ([scene isKindOfClass:[UIWindowScene class]])
          {
            for (UIWindow *w in ((UIWindowScene *) scene).windows)
              if (w.isKeyWindow)
                window = w;
          }
      }
    UIViewController *root = window.rootViewController;
    if (root == nil)
      {
        [controller finish:nil];
        return;
      }
    [root presentViewController:controller animated:YES completion:nil];
  });
}
