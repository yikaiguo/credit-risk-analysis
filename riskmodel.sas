/* create a libname */
libname  rm '/folders/myfolders/riskmodel';

/* import data */
proc import datafile = '/folders/myfolders/riskmodel/LoanData.xlsx'
dbms = xlsx
out = rm.risk_model
replace;
sheet = 'LoanData';
getnames = yes;
run;

/* get data type */
proc contents data =rm.risk_model;
run;
/* 2 date vairable： earliest_cr_line（最早征信记录时间），和last_pymnt_d（当前账户上次还款时间）
，7 char variable, and the rest are num variable */

/* Part 1: 线性模型 Linear Regression Model*/
/* version 1 (v1) */

/*Modification to date variables:把earliest_cr_line换成距现在过了几个月（mths_to_prsnt)；last_pymnt_d
基本上都固定月份，可以换成catagorial variable （last_pymnt_mth)*/
data rm.risk_model_v1;
set rm.risk_model;
a = '01oct2018'd;
mths_to_prsnt = intck('month',earliest_cr_line,a,'continuous');
run; 

/*看下last_pymnt_d有几个月*/
proc sql;
select distinct last_pymnt_d from rm.risk_model_v1;
quit;

/*换成catagorial variable*/
data rm.risk_model_v1;
set rm.risk_model_v1;
last_pymnt_m = month(last_pymnt_d);/*last_pymnt_m is a new num variable*/
if last_pymnt_m = 10 then last_pymnt_mth ='Oct';/*last_pymnt_mth is a new char variable*/
else if last_pymnt_m = 9 then last_pymnt_mth ='Sep';
else if last_pymnt_m = 8 then last_pymnt_mth ='Aug';
else if last_pymnt_m = 7 then last_pymnt_mth ='Jul';
else if last_pymnt_m = 6 then last_pymnt_mth = 'Jun';
else last_pymnt_mth = 'N/A';
run;


/*run linear regression*/
proc glmselect data=RM.RISK_MODEL_V1 outdesign(addinputvars)=Work.reg_design;
	class term sub_grade home_ownership verification_status loan_status purpose 
		addr_state last_pymnt_mth / param=glm;
	model loan_amnt=int_rate installment annual_inc dti delinq_2yrs inq_last_6mths 
		mths_since_last_delinq mths_since_last_record open_acc revol_bal revol_util 
		total_acc total_pymnt last_pymnt_amnt inq_last_12m acc_open_past_24mths 
		chargeoff_within_12_mths delinq_amnt mort_acc mths_since_recent_bc 
		mths_since_recent_bc_dlq mths_since_recent_inq mths_since_recent_revol_delinq 
		num_accts_ever_120_pd mths_to_prsnt term sub_grade home_ownership 
		verification_status loan_status purpose addr_state last_pymnt_mth / 
		showpvalues selection=none;
run;

proc reg data=Work.reg_design alpha=0.05;
	where term is not missing and sub_grade is not missing and home_ownership is 
		not missing and verification_status is not missing and loan_status is not 
		missing and purpose is not missing and addr_state is not missing and 
		last_pymnt_mth is not missing;
	model loan_amnt=&_GLSMOD /;
	run;
quit;

proc delete data=Work.reg_design;
run;
/* 结果：F-test p-value很小，但是这个model只用了200多个数据，其他2万多个missing value被自动忽略了 */


/* **NOTE：In real business cases，如果遇到missing value 太多的情况，我会做一些Research，
了解这些数据是干什么用的, 看情况然后进行处理，如 1.Add mean inputation 2. Last Value Carry Forward
3. Add Catogorial Variable of 'missing' 4. Delete Data 等。这里为了节省时间我就删除了这些数据*/


/*v2:把有较多missing value的columns删除，从其他完整数据里选出有价值的variables加入模型*/
/*根据观察，有4个Column有较多的missing value，并把这些columns删除 */
data rm.risk_model_v2;
set rm.risk_model_v1;
drop mths_since_last_delinq mths_since_last_record mths_since_recent_bc_dlq mths_since_recent_revol_delinq;
run;

/* run linear regression */
proc glmselect data=RM.RISK_MODEL_V2 outdesign(addinputvars)=Work.reg_design;
	class term sub_grade home_ownership verification_status loan_status purpose 
		addr_state last_pymnt_mth / param=glm;
	model loan_amnt=int_rate installment annual_inc dti delinq_2yrs inq_last_6mths 
		open_acc revol_bal revol_util total_acc total_pymnt last_pymnt_amnt 
		inq_last_12m acc_open_past_24mths chargeoff_within_12_mths delinq_amnt 
		mort_acc mths_since_recent_bc mths_since_recent_inq num_accts_ever_120_pd 
		mths_to_prsnt term sub_grade home_ownership verification_status loan_status 
		purpose addr_state last_pymnt_mth / showpvalues selection=none;
run;

proc reg data=Work.reg_design alpha=0.05;
	where term is not missing and sub_grade is not missing and home_ownership is 
		not missing and verification_status is not missing and loan_status is not 
		missing and purpose is not missing and addr_state is not missing and 
		last_pymnt_mth is not missing;
	model loan_amnt=&_GLSMOD /;
	run;
quit;

proc delete data=Work.reg_design;
run;
/*结果: 还有部分missing value, 不过sample size已经够大，可以继续分析。
F-value~= 7500, p-value< 0.0001. 有较多variable的p-value<0.05;incercept is insignificant */

/* 去除intercept，来得到一个less-biased varaible p-value。
因为dependent varaiables 较多，所以用stepwise method 筛选出最优的几个*/
proc glmselect data=RM.RISK_MODEL_V2 outdesign(addinputvars)=Work.reg_design;
	class term sub_grade home_ownership verification_status loan_status purpose 
		addr_state last_pymnt_mth / param=glm;
	model loan_amnt=int_rate installment annual_inc dti delinq_2yrs inq_last_6mths 
		open_acc revol_bal revol_util total_acc total_pymnt last_pymnt_amnt 
		inq_last_12m acc_open_past_24mths chargeoff_within_12_mths delinq_amnt 
		mort_acc mths_since_recent_bc mths_since_recent_inq num_accts_ever_120_pd 
		mths_to_prsnt term sub_grade home_ownership verification_status loan_status 
		purpose addr_state last_pymnt_mth / showpvalues noint selection=stepwise
    
   (select=sbc stop=sbc choose=sbc);
run;

proc reg data=Work.reg_design alpha=0.05;
	where term is not missing and sub_grade is not missing and home_ownership is 
		not missing and verification_status is not missing and loan_status is not 
		missing and purpose is not missing and addr_state is not missing and 
		last_pymnt_mth is not missing;
	model loan_amnt=&_GLSMOD / noint;
	run;
quit;

proc delete data=Work.reg_design;
run;

/* 结论：在线性模型中，如下变量（按重要程度）可以用来Model loan_amnt：1. installment 2.
term 3.sub_grade 4. mort_acc 5. verification_status 6. revol_bal 7.purpose 
8.annual_inc 9.acc_open_past_24mths*/

/*Possible Improvements: 1.更好的处理missing value, 具体方法code里面有提 
2.用更准确的Numerical Variables来代替Classification Variables. 比如信用等级可以用FICO scores代替
3.分析各个dependent variable之间的Collinearity，从而进一步剔除重复的Variables*/


/* Part 2: 逻辑回归模型 Logistic Regression Model*/

/*Data Exploration：选出每个int_rate对应的信用等级*/
proc sql;
select distinct int_rate, sub_grade from rm.risk_model_v2
order by int_rate;
quit;

/* NOTE：6% 对应的c2, 应该是输错了，把它删除*/
data rm.risk_model_v2;
set rm.risk_model_v2;
if int_rate = 0.06 then delete;
run;

/*run logistic regression*/
proc logistic data =rm.risk_model_v2 descending; /*用最好的信用记录A1做参照*/
model sub_grade = int_rate / link = glogit;
run;

proc logistic data =rm.risk_model_v2;/*用最差的G5做参照*/
model sub_grade = int_rate / link = glogit;
run;

/*结果和分析见pdf*/

/* Part 3: K-Means模型 K-Means Model*/
/* 免费版SAS算法选择有限！*/

/*根据R-square来选择分多少组，alpha = 0.05的时候，分7组*/
ods noproctitle;

proc stdize data=RM.RISK_MODEL_V2 out=Work._std_ method=range;
	var int_rate;
run;

proc fastclus data=Work._std_ maxclusters=7 maxiter=100;
	var int_rate;
run;

proc delete data=Work._std_;
run;

/*根据R-square来选择分多少组，alpha = 0.01的时候，分14组*/
ods noproctitle;

proc stdize data=RM.RISK_MODEL_V2 out=Work._std_ method=range;
	var int_rate;
run;

proc fastclus data=Work._std_ maxclusters=14 maxiter=100;
	var int_rate;
run;

proc delete data=Work._std_;
run;

/*如果像原有数据一样分成34个信用等级, 此时R-Sqaure = 1*/
ods noproctitle;

proc stdize data=RM.RISK_MODEL_V2 out=Work._std_ method=range;
	var int_rate;
run;

proc fastclus data=Work._std_ maxclusters=34 maxiter=100 out = rm.risk_model_v3;
	var int_rate;
run;

proc delete data=Work._std_;
run;

/*其他分析见pdf文件*/