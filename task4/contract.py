from web3 import Web3
import time



story_rpc_url = "https://story-testnet.nodeinfra.com"
web3 = Web3(Web3.HTTPProvider(story_rpc_url))

CONTRACT_ADDRESS = "0xCCcCcC0000000000000000000000000000000001"

METHOD_SIGNATURE = b'\x8f\x37\xec\x19'

def count_method_calls(start_block, end_block, batch_size=100):
    call_count = 0
    total_blocks = end_block - start_block + 1
    processed_blocks = 0

    for batch_start in range(start_block, end_block + 1, batch_size):
        batch_end = min(batch_start + batch_size - 1, end_block)
        
        for block_number in range(batch_start, batch_end + 1):
            try:
                block = web3.eth.get_block(block_number, full_transactions=True)
                
                for tx in block.transactions:
                    if tx.get('to') and tx['to'].lower() == CONTRACT_ADDRESS.lower() and tx['input'].startswith(METHOD_SIGNATURE):
                        call_count += 1
            except Exception as e:
                print(f"block :  {block_number} error: {e}")
        
        processed_blocks += (batch_end - batch_start + 1)
        progress = (processed_blocks / total_blocks) * 100
        print(f"success : {progress:.2f}% (block {batch_end}/{end_block})")

    return call_count

def main():
    if not web3.is_connected():
        print("Story Network error.")
        return

    try:
        latest_block = web3.eth.block_number
        print(f"current Story BlockHeight: {latest_block}")
        
        start_block = int(input("Insert Start Block: "))
        end_block = int(input("Insert End Block (If you enter 0, up to the latest block): "))
        
        if end_block == 0:
            end_block = latest_block
        
        print(f"Block {start_block} ~ {end_block} Scanning...")
        
        call_count = count_method_calls(start_block, end_block)
        
        
        print(f"\nResult:")
        print(f"Method 0x8f37ec19 Call : {call_count}")
        print(f"Scanning Block Range: {start_block} - {end_block}")
    
    except Exception as e:
        print(f"error: {e}")

if __name__ == "__main__":
    main()