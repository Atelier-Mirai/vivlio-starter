#include <stdio.h>

/*
 * 半加算器のアセンブリ実装
 * 
 * half_adder:
 *     # 入力値をレジスタにロード
 *     movl input_a, %eax    # A を eax にロード
 *     movl input_b, %ebx    # B を ebx にロード
 *     
 *     # S = A XOR B の計算
 *     movl %eax, %ecx       # A を ecx にコピー
 *     xorl %ebx, %ecx       # ecx = A XOR B
 *     movl %ecx, output_s   # 結果をSに保存
 *     
 *     # C = A AND B の計算
 *     movl %eax, %edx       # A を edx にコピー
 *     andl %ebx, %edx       # edx = A AND B
 *     movl %edx, output_c   # 結果をCに保存
 *     
 *     ret
 */

// C言語での半加算器実装（アセンブリ相当の動作）
void half_adder(int a, int b, int *s, int *c) {
    // アセンブリでの XOR 操作に相当
    *s = a ^ b;  // S = A XOR B
    
    // アセンブリでの AND 操作に相当
    *c = a & b;  // C = A AND B
}

int main() {
    // 半加算器の真理値表:
    // ===================
    // A | B | S | C | 説明
    // --|---|---|---|--------
    // 0 | 0 | 0 | 0 | 0+0=0
    // 0 | 1 | 1 | 0 | 0+1=1
    // 1 | 0 | 1 | 0 | 1+0=1
    // 1 | 1 | 0 | 1 | 1+1=10(2進)
    
    // 対応するアセンブリ命令:
    // ========================
    // XOR演算 (S = A XOR B):
    //   xorl %ebx, %ecx    # ecx = A XOR B
    //
    // AND演算 (C = A AND B):
    //   andl %ebx, %edx    # edx = A AND B

    // 論理回路の動作:
    // - OR ゲート: A と B の少なくとも一方が1なら1
    // - NOT ゲート: 入力を反転
    // - AND ゲート: A と B が両方1なら1
    // - 最終的に S = A XOR B, C = A AND B
    
    // 実際の計算例
    printf("\n計算例:\n");
    printf("=======\n");
    int s, c;
    
    half_adder(0, 0, &s, &c);
    printf("0 + 0 = %d%d (2進数)\n", c, s);
    printf("      =  %d (10進数)\n", c * 2 + s);
    
    half_adder(0, 1, &s, &c);
    printf("0 + 1 = %d%d (2進数)\n", c, s);
    printf("      =  %d (10進数)\n", c * 2 + s);
    
    half_adder(1, 0, &s, &c);
    printf("1 + 0 = %d%d (2進数)\n", c, s);
    printf("      =  %d (10進数)\n", c * 2 + s);
    
    half_adder(1, 1, &s, &c);
    printf("1 + 1 = %d%d (2進数)\n", c, s);
    printf("      =  %d (10進数)\n", c * 2 + s);

    return 0;
}
