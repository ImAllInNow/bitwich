pragma solidity ^0.4.23;

import "./Pausable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

contract BitWich is Pausable {
    using SafeMath for uint;
    using SafeERC20 for ERC20;

    event LogBought(address indexed buyer, uint buyCost, uint amount);
    event LogSold(address indexed seller, uint sellValue, uint amount);
    event LogPriceChanged(uint newBuyCost, uint newSellValue);

    // Name of the token on which this bitwich contract operates
    string public erc20TokenName;

    // ERC20 contract to operate over
    ERC20 public erc20Contract;

    // amount bought - amount sold = amount willing to buy from others
    uint public netAmountBought;

    // number of tokens that can be bought from contract per wei
    uint public buyCost;

    // number of tokens that can be sold to contract per wei
    uint public sellValue;

    constructor(uint _buyCost,
                uint _sellValue,
                string _tokenName,
                address _erc20ContractAddress) public {
        require(_buyCost > 0);
        require(_sellValue > 0);

        buyCost = _buyCost;
        sellValue = _sellValue;
        erc20TokenName = _tokenName;
        erc20Contract = ERC20(_erc20ContractAddress);
    }

    /* ACCESSORS */
    function amountForSale() external view returns (uint) {
        return erc20Contract.balanceOf(address(this));
    }

    // Accessor for the cost in wei of buying a certain amount of tokens.
    function getBuyCost(uint _amount) external view returns(uint) {
        uint cost = _amount.div(buyCost);
        if (cost > 0 && cost % 10 != 0) {
            cost = cost.add(1); // Handles truncating error for odd buyCosts
        }
        return cost;
    }

    // Accessor for the value in wei of selling a certain amount of tokens.
    function getSellValue(uint _amount) external view returns(uint) {
        return _amount.div(sellValue);
    }

    /* PUBLIC FUNCTIONS */
    // Perform the buy of tokens for ETH and add to the net amount bought
    function buy(uint _minAmountDesired) external payable whenNotPaused {
        processBuy(msg.sender, _minAmountDesired);
    }

    // Perform the sell of tokens, send ETH to the seller, and reduce the net amount bought
    // NOTE: seller must call ERC20.approve() first before calling this,
    //       unless they can use ERC20.approveAndCall() directly
    function sell(uint _amount, uint _weiExpected) external whenNotPaused {
        processSell(msg.sender, _amount, _weiExpected);
    }

    /* INTERNAL FUNCTIONS */
    // NOTE: _minAmountDesired protects against cost increase between send time and process time
    function processBuy(address _buyer, uint _minAmountDesired) internal {
        uint amountPurchased = msg.value.mul(buyCost);
        require(erc20Contract.balanceOf(address(this)) >= amountPurchased);
        require(amountPurchased >= _minAmountDesired);

        netAmountBought = netAmountBought.add(amountPurchased);
        emit LogBought(_buyer, buyCost, amountPurchased);

        erc20Contract.safeTransfer(_buyer, amountPurchased);
    }

    // NOTE: _weiExpected protects against a value decrease between send time and process time
    function processSell(address _seller, uint _amount, uint _weiExpected) internal {
        require(netAmountBought >= _amount);
        require(erc20Contract.allowance(_seller, address(this)) >= _amount);
        uint value = _amount.div(sellValue); // tokens divided by (tokens per wei) equals wei
        require(value >= _weiExpected);
        assert(address(this).balance >= value); // contract should always have enough wei

        netAmountBought = netAmountBought.sub(_amount);
        emit LogSold(_seller, sellValue, _amount);

        erc20Contract.safeTransferFrom(_seller, address(this), _amount);
        _seller.transfer(value);
    }

    // NOTE: this should never return true unless this contract has a bug
    function lacksFunds() external view returns(bool) {
        return address(this).balance < netAmountBought.div(sellValue);
    }

    /* OWNER FUNCTIONS */
    // Owner function to check how much extra ETH is available to cash out
    function amountAvailableToCashout() external view onlyOwner returns (uint) {
        uint requiredBalance = netAmountBought.div(sellValue);
        return address(this).balance.sub(requiredBalance);
    }

    // Owner function for cashing out extra ETH not needed for buying tokens
    function cashout() external onlyOwner {
        uint requiredBalance = netAmountBought.div(sellValue);

        // safe math handles case where requiredBalance > this.balance
        owner.transfer(address(this).balance.sub(requiredBalance));
    }

    // Owner function for closing the paused contract and cashing out all tokens and ETH
    function close() public onlyOwner whenPaused {
        erc20Contract.transfer(owner, erc20Contract.balanceOf(address(this)));
        selfdestruct(owner);
    }

    // Owner accessor to get how much ETH is needed to send
    // in order to change sell price to proposed price
    function extraBalanceNeeded(uint _propsedSellValue) external view onlyOwner returns (uint) {
        uint requiredBalance = netAmountBought.div(_propsedSellValue);
        return (requiredBalance > address(this).balance) ? requiredBalance.sub(address(this).balance) : 0;
    }

    // Owner function for adjusting prices (need to add ETH if raising sell price)
    function adjustPrices(uint _buyCost, uint _sellValue) external payable onlyOwner whenPaused {
        buyCost = _buyCost == 0 ? buyCost : _buyCost;
        sellValue = _sellValue == 0 ? sellValue : _sellValue;

        uint requiredBalance = netAmountBought.div(sellValue);
        require(msg.value.add(address(this).balance) >= requiredBalance);

        emit LogPriceChanged(buyCost, sellValue);
    }

    // Owner can transfer out any accidentally sent ERC20 tokens
    // excluding the token intended for this contract
    function transferAnyERC20Token(address _address, uint _tokens) external onlyOwner {
        if (_address != address(erc20Contract)) {
            ERC20(_address).safeTransfer(owner, _tokens);
        }
    }
}
