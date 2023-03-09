
#import "ViewController.h"
#import "ffmpeg.h"
#import "EncodeH264.h"

//======================================config region======================================

int is_decodeYUV = 0;

//======================================config region======================================


extern bool ENCODE_DONE;
@interface ViewController (){
    EncodeH264 *_h264;
}
@end

@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (is_decodeYUV == 1) {
        [self decodeYUV];
    }
    //初始化视频编码
    _h264 = [[EncodeH264 alloc] init];
    //创建视频解码会话
    [_h264 createEncodeSession];
    [_h264 openfile];
    NSLog(@"==========openfile==========");
    [_h264 yuv2h264];
    NSLog(@"==========yuv2h264==========");
    [_h264 closefile];
    NSLog(@"==========comple convert==========");

}

- (void)decodeYUV{
    [self createDocumentsTestDir];
    
    NSString *Documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    
    NSString *command_str = [NSString stringWithFormat:@"ffmpeg -y -i %@/src.mp4 -f segment -segment_time 0.01 %@/test/frames%%d.yuv",Documents,Documents];
    // 分割字符串
    NSMutableArray  *argv_array  = [command_str componentsSeparatedByString:(@" ")].mutableCopy;
    // 获取参数个数
    int argc = (int)argv_array.count;
    // 遍历拼接参数
    char **argv = calloc(argc, sizeof(char*));
    for(int i=0; i<argc; i++)
    {
        NSString *codeStr = argv_array[i];
        argv_array[i]     = codeStr;
        argv[i]      = (char *)[codeStr UTF8String];
    }
    ffmpeg_main(argc, argv);
}

- (IBAction)startCode:(UIButton *)sender {
    sender.selected = !sender.selected;
    if (sender.selected) {
        [sender setTitle:@"clear sandboxie" forState:UIControlStateNormal];
        //清空沙盒document内容
//        [self clearDocument];
    }
    
    if(ENCODE_DONE) {
        [sender setTitle:@"cleaed" forState:UIControlStateNormal];
    }
    NSLog(@"Encode session complete,  frames have been encoded");
}

- (void)clearDocument{
    NSString *DocumentsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:DocumentsPath];
    for (NSString *fileName in enumerator) {
        [[NSFileManager defaultManager] removeItemAtPath:[DocumentsPath stringByAppendingPathComponent:fileName] error:nil];
    }
}
-(void) createDocumentsTestDir{
    NSString *DocumentsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *testDir= [NSString stringWithFormat:@"%@/test",DocumentsPath];
    //判断createPath路径文件夹是否已存在，此处createPath为需要新建的文件夹的绝对路径
    if ([[NSFileManager defaultManager] fileExistsAtPath:testDir]) {
        //文件夹已存在
        return;
    } else {
        //创建文件夹
        [[NSFileManager defaultManager] createDirectoryAtPath:testDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
}


@end
