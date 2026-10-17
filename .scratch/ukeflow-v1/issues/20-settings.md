# 20: 设置页

**What to build:** 设置页与 settings 持久化:A4 参考音高(调音器消费)、默认 BPM(节拍器/跟练消费),为后续设置提供统一存放处。

**Blocked by:** 19 调音器正式页

**Status:** ready-for-agent

- [ ] 改 A4(如 440→432)后调音器目标频率即时变化
- [ ] 默认 BPM 对节拍器/跟练生效
- [ ] 设置持久化(重启仍在)
- [ ] settings DAO 有测试

## Comments

- 2026-10-17 (实现会话): 设置页与持久化落地。①存储:`settings` 键值表(key 主键,value 文本——为后续字符串/其他类型设置留位不迁表),schemaVersion 3→4(createAll 幂等),`SettingsDao.getInt/setInt`+`SettingsKeys` 键常量;②供给:`settingsProvider`(Notifier:缺省 440/80→异步加载落库值,setter 即时换状态+写透 DAO;`ready` 定序——初载未落地的写透不得被迟到加载覆盖;加载失败保留缺省记日志,与 databaseWarmup 同口径);③A4 同源接线(pitch_math 注释预告兑现):`UkeString` 加 midi+`frequencyAt(a4)`(440 处与既有常量重合有回归锚),调音器目标频率/偏差判准/空弦试音音源/读数音名标注(TunerFilter.push 增 a4 参)四处同源换算——**和弦示范音/跟练伴奏音源保持 440 系**,票面括号明确「调音器消费」,432 用户与伴奏的听感差异验收时提请决策(若要全库随动,归后续票);④默认 BPM:节拍器初始值(watch 设置)、跟练 `prepareFor` 无 tempo 谱回退值(进谱时 read;指弹谱 tempo 为校验必填无此回退面)。**节拍器缺省 120 收拢归一为 80**(与训练器/跟练慢练起步同源;训练器不在票面消费清单,未接线,验收时可提)。⑤页面:第 5 页签「设置」;`BpmControl` 参数化(label/keyPrefix)通用化为 `StepSliderControl` 改名迁 core/ui(三页调用点机械更名,无测试键消费方)。测试 546→562 全绿,analyzer 零告警;消费方测试 override 派生 provider 隔离不触真库(drift LazyDatabase 构造即开联,单测环境未处理异步错误,详见各测试注释)。真机验收项:改 A4 后调音器目标即时变化/默认 BPM 两处生效/重启仍在(杀进程重开)。

- 2026-10-17 (评审落地): 双轴评审(Standards/Spec)处置。①两 setter 补 `ref.mounted` 守卫(await ready 之后,与 _load 同纪律);②竞态契约补防回归测试——同同步轮「触发 build+立即写」,破序实现(删 await ready)红验证终态回滚 432,定序实现绿;③节拍器 watch 注释诚实化:启动初载落地也会触发重建(冷启毫秒级 vs 人开到节拍器数秒,窗口实际不可达,代价上界重进页 warmup 一次),原注释「重置只落在空闲态」过度断言;④GLOSSARY 补「参考音」「默认 BPM」两词条。验收面事实补充:内置五曲均带 `{tempo}`,设置默认 BPM 对内置谱无感,作用面=导入的无 tempo 谱回退+节拍器初始值。记提取债(不当场跨三特性文件收拢):BPM 钳制域 40–208 现四处各写(settings_providers/节拍器/弹唱跟练/训练器各自 minBpm/maxBpm,仅注释互指),后续提共享常量时一并收;A4 一值三形(DAO text/状态 int/provider double)当前规模可接受。563 绿,analyzer 零告警。
